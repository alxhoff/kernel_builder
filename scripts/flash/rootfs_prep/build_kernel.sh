#!/bin/bash

# Build a Jetson kernel for a given JetPack/L4T release.
#
# Supports both the JP5 (direct make) flow and the JP6 (nvbuild.sh) flow.
# The flow is selected automatically from the --patch value; the JP5 and
# JP6 kernel trees have diverged enough that the actual build command
# differs, but everything else (arg parsing, patch download, defconfig
# fetch, rootfs install, extlinux FDT fix-up) is shared.

set -e

TEGRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS_ROOT_DIR="$TEGRA_DIR/rootfs"
KERNEL_SRC_ROOT="$TEGRA_DIR/kernel_src"
MENUCONFIG=false
LOCALVERSION=""
PATCH="5.1.3"
PATCH_SOURCE=false

declare -A JETPACK_L4T_MAP=(
    [5.1.2]=35.4.1
    [5.1.3]=35.5.0
    [5.1.4]=35.6.0
    [5.1.5]=35.6.1
    [6.0DP]=36.2
    [6.1]=36.4
    [6.2]=36.4.3
)

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo."
    exit 1
fi

if [ -z "$SUDO_USER" ]; then
    echo "Error: This script must be run using sudo, not as root directly."
    exit 1
fi

show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --patch VERSION     JetPack version (default: $PATCH). Available:"
    echo "                      ${!JETPACK_L4T_MAP[*]}"
    echo "  --menuconfig        Open menuconfig before compiling (JP5 only)"
    echo "  --localversion STR  Set the LOCALVERSION for the kernel build"
    echo "  -h, --help          Show this help message"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --patch)
            PATCH="$2"
            PATCH_SOURCE=true
            shift 2
            ;;
        --menuconfig)
            MENUCONFIG=true
            shift
            ;;
        --localversion)
            LOCALVERSION="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

if [[ -z "${JETPACK_L4T_MAP[$PATCH]}" ]]; then
    echo "Error: Unsupported JetPack version '$PATCH'. Use --help to see available versions."
    exit 1
fi

# JP6 uses nvbuild.sh, JP5 uses plain make.
JP_MAJOR="${PATCH%%.*}"
if [[ "$JP_MAJOR" == "6"* ]]; then
    BUILD_FLOW="jp6"
    TOOLCHAIN_DIR="$TEGRA_DIR/toolchain"
    CROSS_COMPILE="$TOOLCHAIN_DIR/bin/aarch64-buildroot-linux-gnu-"
else
    BUILD_FLOW="jp5"
    TOOLCHAIN_DIR="$TEGRA_DIR/toolchain/bin"
    CROSS_COMPILE="$TOOLCHAIN_DIR/aarch64-buildroot-linux-gnu-"
fi
MAKE_ARGS="ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE -j$(nproc)"

KERNEL_SRC_DIR_BASE="$KERNEL_SRC_ROOT/kernel"
KERNEL_SRC_SUBDIR=$(find "$KERNEL_SRC_DIR_BASE" -mindepth 1 -maxdepth 1 -type d -name "kernel*" | head -n 1)
if [ -z "$KERNEL_SRC_SUBDIR" ]; then
    echo "Error: Could not find kernel source subdirectory in $KERNEL_SRC_DIR_BASE"
    exit 1
fi

if [ "$BUILD_FLOW" = "jp5" ]; then
    # JP5 expects the source at a stable path; rename for compatibility.
    KERNEL_SRC="$KERNEL_SRC_DIR_BASE/kernel"
    if [[ "$KERNEL_SRC_SUBDIR" != "$KERNEL_SRC" ]]; then
        echo "Renaming kernel source directory to $KERNEL_SRC"
        sudo mv "$KERNEL_SRC_SUBDIR" "$KERNEL_SRC"
    fi
else
    KERNEL_SRC="$KERNEL_SRC_SUBDIR"
    echo "Using kernel source at $KERNEL_SRC"
fi

echo "Checking for toolchain..."
if [ ! -d "$TOOLCHAIN_DIR" ]; then
    echo "Toolchain not found. Cloning..."
    sudo git clone --depth=1 git@gitlab.com:cartken/kernel-os/jetson-linux-toolchain "$TOOLCHAIN_DIR"
    echo "Toolchain cloned successfully."
fi

if [ ! -d "$KERNEL_SRC" ]; then
    echo "Error: Kernel source directory not found at $KERNEL_SRC"
    exit 1
fi

echo "Checking git status in kernel source..."
# Needed when running git as root against another user's working tree.
sudo git config --global --add safe.directory "$KERNEL_SRC_ROOT"
if [ ! -d "$KERNEL_SRC_ROOT/.git" ]; then
    echo "Initializing git repository for patch management..."
    (cd "$KERNEL_SRC_ROOT" && git init && git config user.name "KernelBuilder" && git config user.email "builder@localhost" && git add . && git commit --no-gpg-sign -m "Initial kernel source")
else
    if (cd "$KERNEL_SRC_ROOT" && git rev-parse --verify HEAD &>/dev/null); then
        echo "Resetting kernel source to clean state..."
        (cd "$KERNEL_SRC_ROOT" && git reset --hard HEAD && git clean -fdx)
    else
        echo "No commits found in kernel source. Skipping git reset."
    fi
fi

GIT_PATCH_URL="https://api.github.com/repos/alxhoff/kernel_builder/contents/patches/$PATCH"

if [ "$PATCH_SOURCE" = true ]; then
    sudo mkdir -p "$TEGRA_DIR/kernel_patches"
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is not installed. Please install jq to proceed."
        exit 1
    fi

    echo "Fetching list of patches for $PATCH kernel..."
    CURL_RESPONSE=$(curl -s -w "%{http_code}" "$GIT_PATCH_URL")
    HTTP_CODE=${CURL_RESPONSE: -3}
    PATCH_LIST=${CURL_RESPONSE:0:-3}

    if [ "$HTTP_CODE" != "200" ]; then
        echo "Error: Failed to retrieve patch list from GitHub (HTTP code: $HTTP_CODE)."
        echo "Response: $PATCH_LIST"
        exit 1
    fi

    if ! echo "$PATCH_LIST" | jq -e 'type=="array"' > /dev/null 2>&1; then
        echo "Error: Invalid JSON response from GitHub (not an array)."
        echo "Response: $PATCH_LIST"
        exit 1
    fi

    echo "$PATCH_LIST" | jq -r '.[] | select(.name != ".gitkeep" and .name != ".gitignore") | .download_url' | grep -v '^$' | while read -r FILE_URL; do
        if [[ -z "$FILE_URL" || "$FILE_URL" == "null" ]]; then
            echo "Skipping invalid or empty patch URL."
            continue
        fi

        FILE_NAME=$(basename "$FILE_URL")
        if [[ "$FILE_NAME" == ".gitkeep" || "$FILE_NAME" == ".gitignore" ]]; then
            echo "Skipping $FILE_NAME (not a patch file)."
            continue
        fi

        PATCH_FILE="$TEGRA_DIR/kernel_patches/$FILE_NAME"
        echo "Downloading $FILE_NAME..."
        wget -v --show-progress -O "$PATCH_FILE" "$FILE_URL"

        if [[ -f "$PATCH_FILE" ]]; then
            echo "Applying patch $FILE_NAME..."
            patch -p1 -d "$KERNEL_SRC_ROOT" --batch --forward < "$PATCH_FILE" || echo "Warning: Some hunks failed!"
        else
            echo "Error: Patch file $FILE_NAME not found!"
            exit 1
        fi
    done
fi

cd "$KERNEL_SRC"

defconfig_path="$KERNEL_SRC/arch/arm64/configs/defconfig"
echo "Downloading cartken defconfig..."
sudo wget -O "$defconfig_path" "https://raw.githubusercontent.com/alxhoff/kernel_builder/refs/heads/master/configs/$PATCH/defconfig"
echo "cartken_defconfig downloaded successfully."

if [ "$BUILD_FLOW" = "jp5" ]; then
    sudo make -C "$KERNEL_SRC" $MAKE_ARGS mrproper

    if [ "$MENUCONFIG" = true ]; then
        echo "Running menuconfig..."
        sudo make -C "$KERNEL_SRC" $MAKE_ARGS menuconfig
    fi

    if [ -n "$LOCALVERSION" ]; then
        echo "Building kernel with LOCALVERSION=$LOCALVERSION..."
        sudo make -C "$KERNEL_SRC" $MAKE_ARGS LOCALVERSION="$LOCALVERSION" defconfig
        sudo make -C "$KERNEL_SRC" $MAKE_ARGS LOCALVERSION="$LOCALVERSION"
        sudo make -C "$KERNEL_SRC" $MAKE_ARGS LOCALVERSION="$LOCALVERSION" modules_install INSTALL_MOD_PATH="$ROOTFS_ROOT_DIR"
    else
        echo "Building kernel using cartken_defconfig..."
        sudo make -C "$KERNEL_SRC" $MAKE_ARGS defconfig
        sudo make -C "$KERNEL_SRC" $MAKE_ARGS
        sudo make -C "$KERNEL_SRC" $MAKE_ARGS modules_install INSTALL_MOD_PATH="$ROOTFS_ROOT_DIR"
    fi

    KERNEL_IMAGE_SRC="$KERNEL_SRC/arch/arm64/boot/Image"
    DTB_NAMES=(
        "tegra234-p3701-0000-p3737-0000.dtb"
        "tegra234-p3701-0005-p3737-0000.dtb"
        "tegra234-p3701-0004-p3737-0000.dtb"
    )
    DTB_SRC_DIR="$KERNEL_SRC/arch/arm64/boot/dts/nvidia"
    KERNEL_BUILD_DIR=""
else
    # JP6: nvbuild.sh drives the build.
    echo "Setting LOCALVERSION in defconfig..."
    echo "CONFIG_LOCALVERSION=\"$LOCALVERSION\"" | sudo tee -a "$defconfig_path"
    echo "CONFIG_LOCALVERSION_AUTO=n" | sudo tee -a "$defconfig_path"

    NVBUILD_SCRIPT="$KERNEL_SRC_ROOT/nvbuild.sh"
    if [ ! -f "$NVBUILD_SCRIPT" ]; then
        echo "Error: nvbuild.sh not found at $NVBUILD_SCRIPT"
        exit 1
    fi

    export CROSS_COMPILE
    export ARCH=arm64
    export INSTALL_MOD_PATH="$ROOTFS_ROOT_DIR"

    pushd "$KERNEL_SRC_ROOT" > /dev/null
    echo "Running nvbuild.sh to build kernel and modules..."
    sudo -E "./nvbuild.sh"
    echo "Running nvbuild.sh to install kernel and modules..."
    sudo -E "./nvbuild.sh" -i
    popd > /dev/null

    KERNEL_OUT_DIR="$KERNEL_SRC_ROOT/kernel_out"
    KERNEL_BUILD_DIR="$KERNEL_OUT_DIR/kernel/$(basename "$KERNEL_SRC")"
    KERNEL_IMAGE_SRC="$KERNEL_BUILD_DIR/arch/arm64/boot/Image"
    DTB_NAMES=("tegra234-p3737-0000+p3701-0000-nv.dtb")
    DTB_SRC_DIR="$KERNEL_OUT_DIR/kernel-devicetree/generic-dts/dtbs"
fi

KERNEL_IMAGE_DEST="$TEGRA_DIR/kernel/"
ROOTFS_BOOT_DIR="$ROOTFS_ROOT_DIR/boot/"
KERNEL_DTB_DIR="$TEGRA_DIR/kernel/dtb"
ROOTFS_DTB_DIR="$ROOTFS_BOOT_DIR/dtb"
ROOTFS_EXTLINUX_DIR="$ROOTFS_BOOT_DIR/extlinux"
ROOTFS_EXTLINUX_FILE="$ROOTFS_EXTLINUX_DIR/extlinux.conf"

sudo mkdir -p "$KERNEL_IMAGE_DEST"
sudo mkdir -p "$ROOTFS_DTB_DIR"

if [ -f "$KERNEL_IMAGE_SRC" ]; then
    echo "Copying kernel Image to $KERNEL_IMAGE_DEST..."
    sudo cp -v "$KERNEL_IMAGE_SRC" "$KERNEL_IMAGE_DEST"
    echo "Copying kernel Image to $ROOTFS_BOOT_DIR..."
    sudo cp -v "$KERNEL_IMAGE_SRC" "$ROOTFS_BOOT_DIR"
else
    echo "Error: Kernel Image not found at $KERNEL_IMAGE_SRC"
    exit 1
fi

for DTB_NAME in "${DTB_NAMES[@]}"; do
    DTB_SRC="$DTB_SRC_DIR/$DTB_NAME"
    KERNEL_DTB_FILE="$KERNEL_DTB_DIR/$DTB_NAME"
    ROOTFS_DTB_FILE="$ROOTFS_DTB_DIR/$DTB_NAME"
    ROOTFS_ABS_DTB_FILE="/boot/dtb/$DTB_NAME"

    if [ -f "$DTB_SRC" ]; then
        echo "Copying $DTB_NAME to $KERNEL_DTB_FILE..."
        sudo cp -v "$DTB_SRC" "$KERNEL_DTB_FILE"
        echo "Copying $DTB_NAME to $ROOTFS_DTB_FILE..."
        sudo cp -v "$DTB_SRC" "$ROOTFS_DTB_FILE"
    else
        echo "Error: $DTB_NAME not found at $DTB_SRC"
        exit 1
    fi
done

if grep -q "^[[:space:]]*FDT " "$ROOTFS_EXTLINUX_FILE"; then
    sed -i "s|^[[:space:]]*FDT .*|      FDT ${ROOTFS_ABS_DTB_FILE}|" "$ROOTFS_EXTLINUX_FILE"
else
    sed -i "/^[[:space:]]*LINUX /a \      FDT ${ROOTFS_ABS_DTB_FILE}" "$ROOTFS_EXTLINUX_FILE"
fi

echo "Kernel build completed successfully!"

if [ "$BUILD_FLOW" = "jp5" ]; then
    sudo "$TEGRA_DIR/build_third_party_drivers.sh" \
        --kernel-src-root "$KERNEL_SRC" \
        --toolchain "$CROSS_COMPILE" \
        --rootfs-root-dir "$ROOTFS_ROOT_DIR" \
        --tegra-dir "$TEGRA_DIR" \
        --patch "$PATCH"
else
    echo "Reading actual LOCALVERSION from .config"
    CONFIG_FILE="$KERNEL_BUILD_DIR/.config"
    if [ -f "$CONFIG_FILE" ]; then
        ACTUAL_LOCALVERSION=$(grep CONFIG_LOCALVERSION= "$CONFIG_FILE" | cut -d '"' -f 2)
        echo "Actual LOCALVERSION is: $ACTUAL_LOCALVERSION"
    else
        echo "Warning: .config file not found. Using the provided LOCALVERSION."
        ACTUAL_LOCALVERSION="$LOCALVERSION"
    fi

    sudo "$TEGRA_DIR/build_third_party_drivers_jp6.sh" \
        --kernel-src "$KERNEL_SRC" \
        --kernel-out-dir "$KERNEL_BUILD_DIR" \
        --toolchain "$CROSS_COMPILE" \
        --rootfs-root-dir "$ROOTFS_ROOT_DIR" \
        --tegra-dir "$TEGRA_DIR" \
        --patch "$PATCH" \
        --localversion "$ACTUAL_LOCALVERSION"
fi
