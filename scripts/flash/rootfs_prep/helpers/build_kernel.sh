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
SKIP_PATCHES=false
DEFCONFIG_FILE=""
SKIP_THIRD_PARTY_DRIVERS=false
ONLY_OOT_MODULES=false
ONLY_INSTALL_ARTIFACTS=false
PUBLIC_SOURCES=""
DTB_NAME_OVERRIDE=""

declare -A JETPACK_L4T_MAP=(
    [5.1.2]=35.4.1
    [5.1.3]=35.5.0
    [5.1.4]=35.6.0
    [5.1.5]=35.6.1
    [6.0DP]=36.2
    [6.1]=36.4
    [6.2]=36.4.3
    [7.2]=39.2.0
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
    echo "  --defconfig PATH    Use a specific defconfig file (overrides cartken lookup)"
    echo "  --skip-patches      Do not fetch/apply kernel patches from GitHub"
    echo "  --only-oot-modules  Skip kernel compile; build/install NVIDIA OOT modules only (JP6/JP7)"
    echo "  --only-install-artifacts"
    echo "                      Skip nvbuild; copy existing Image/DTB from kernel_out only"
    echo "  --dtb-name NAME     Override the OOT DTB file to install (JP6/JP7)"
    echo "  --public-sources PATH"
    echo "                      public_sources.tbz2 used to supplement JP7 kernel_src"
    echo "  --skip-third-party-drivers"
    echo "                      Skip rtl8192eu/rtl88x2bu out-of-tree driver build"
    echo "  -h, --help          Show this help message"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --patch)
            PATCH="$2"
            shift 2
            ;;
        --skip-patches)
            SKIP_PATCHES=true
            shift
            ;;
        --menuconfig)
            MENUCONFIG=true
            shift
            ;;
        --localversion)
            LOCALVERSION="$2"
            shift 2
            ;;
        --defconfig)
            DEFCONFIG_FILE="$(realpath "$2")"
            shift 2
            ;;
        --skip-third-party-drivers)
            SKIP_THIRD_PARTY_DRIVERS=true
            shift
            ;;
        --only-oot-modules)
            ONLY_OOT_MODULES=true
            shift
            ;;
        --only-install-artifacts)
            ONLY_INSTALL_ARTIFACTS=true
            shift
            ;;
        --dtb-name)
            DTB_NAME_OVERRIDE="$2"
            shift 2
            ;;
        --public-sources)
            PUBLIC_SOURCES="$(realpath "$2")"
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

if [[ "$SKIP_PATCHES" == false ]]; then
    PATCH_SOURCE=true
fi

# JP6/JP7 use nvbuild.sh, JP5 uses plain make.
JP_MAJOR="${PATCH%%.*}"
ensure_jp7_kernel_src_if_needed() {
    local ensure_script="$TEGRA_DIR/ensure_jp7_kernel_src.sh"
    if [[ ! -f "$ensure_script" ]]; then
        ensure_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ensure_jp7_kernel_src.sh"
    fi
    if [[ ! -f "$ensure_script" ]]; then
        echo "Error: ensure_jp7_kernel_src.sh not found." >&2
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$ensure_script"
    ensure_jp7_kernel_src_complete "$KERNEL_SRC_ROOT" "$PUBLIC_SOURCES"
}

if [[ "$JP_MAJOR" == "7"* ]]; then
    BUILD_FLOW="jp6"
    ENSURE_JP7_TOOLCHAIN_SH="$TEGRA_DIR/ensure_jp7_toolchain.sh"
    if [[ ! -f "$ENSURE_JP7_TOOLCHAIN_SH" ]]; then
        ENSURE_JP7_TOOLCHAIN_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ensure_jp7_toolchain.sh"
    fi
    # shellcheck source=helpers/ensure_jp7_toolchain.sh
    source "$ENSURE_JP7_TOOLCHAIN_SH"
    ensure_jp7_toolchain
    TOOLCHAIN_DIR="$JP7_TOOLCHAIN_ROOT/x-tools/aarch64-none-linux-gnu"
    CROSS_COMPILE="$JP7_CROSS_COMPILE"
elif [[ "$JP_MAJOR" == "6"* ]]; then
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
if [[ "$JP_MAJOR" == "7"* ]]; then
    ensure_jp7_toolchain
elif [ ! -d "$TEGRA_DIR/toolchain" ]; then
    echo "Toolchain not found. Cloning..."
    sudo git clone --depth=1 git@gitlab.com:cartken/kernel-os/jetson-linux-toolchain "$TEGRA_DIR/toolchain"
    echo "Toolchain cloned successfully."
fi

if [ ! -d "$KERNEL_SRC" ]; then
    echo "Error: Kernel source directory not found at $KERNEL_SRC"
    exit 1
fi

echo "Checking git status in kernel source..."
# Needed when running git as root against another user's working tree.
sudo git config --global --add safe.directory "$KERNEL_SRC_ROOT"
if [[ "$ONLY_OOT_MODULES" != true ]]; then
    if [ ! -d "$KERNEL_SRC_ROOT/.git" ]; then
        echo "Initializing git repository for patch management..."
        (cd "$KERNEL_SRC_ROOT" && git init && git config user.name "KernelBuilder" && git config user.email "builder@localhost" && git add . && git commit --no-gpg-sign -m "Initial kernel source")
    else
        if (cd "$KERNEL_SRC_ROOT" && git rev-parse --verify HEAD &>/dev/null); then
            echo "Resetting kernel source to clean state..."
            # Only clean the kernel tree. JP6/JP7 OOT/display sources live beside
            # kernel/ and must survive between incremental builds.
            (cd "$KERNEL_SRC_ROOT" && git reset --hard HEAD && git clean -fdx -- kernel/)
        else
            echo "No commits found in kernel source. Skipping git reset."
        fi
    fi
fi

if [[ "$JP_MAJOR" == "7"* ]]; then
    ensure_jp7_kernel_src_if_needed
fi

GIT_PATCH_URL="https://api.github.com/repos/alxhoff/kernel_builder/contents/sources/patches/$PATCH"

if [ "$PATCH_SOURCE" = true ]; then
    sudo mkdir -p "$TEGRA_DIR/kernel_patches"
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is not installed. Please install jq to proceed."
        exit 1
    fi

    echo "Fetching list of patches for $PATCH kernel..."
    CURL_RESPONSE=$(curl -sS --connect-timeout 15 --max-time 45 -w "%{http_code}" "$GIT_PATCH_URL" || true)
    if [[ -z "$CURL_RESPONSE" ]]; then
        echo "Warning: Patch list request timed out or failed for $PATCH. Continuing without patches."
        PATCH_LIST=""
    else
    HTTP_CODE=${CURL_RESPONSE: -3}
    PATCH_LIST=${CURL_RESPONSE:0:-3}

    if [ "$HTTP_CODE" != "200" ]; then
        echo "Warning: No patch series found for $PATCH on GitHub (HTTP $HTTP_CODE). Continuing without patches."
        PATCH_LIST=""
    elif ! echo "$PATCH_LIST" | jq -e 'type=="array"' > /dev/null 2>&1; then
        echo "Warning: Invalid patch list response for $PATCH. Continuing without patches."
        PATCH_LIST=""
    fi

    fi

    if [ -n "$PATCH_LIST" ]; then
    mapfile -t PATCH_URLS < <(echo "$PATCH_LIST" | jq -r '.[] | select(.name != ".gitkeep" and .name != ".gitignore") | .download_url' | grep -v '^$' || true)
    if [ "${#PATCH_URLS[@]}" -eq 0 ]; then
        echo "No kernel patches to apply for $PATCH."
    fi
    for FILE_URL in "${PATCH_URLS[@]}"; do
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
fi

cd "$KERNEL_SRC"

find_kernel_builder_root() {
    local dir="$TEGRA_DIR"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/sources/configs" && -d "$dir/scripts/flash/rootfs_prep" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

is_valid_defconfig() {
    local defconfig_file="$1"
    local config_lines=0
    [[ -f "$defconfig_file" ]] || return 1
    config_lines="$(grep -c '^CONFIG_' "$defconfig_file" 2>/dev/null || echo 0)"
    [[ "$config_lines" -ge 50 ]]
}

restore_stock_nvidia_defconfig() {
    local defconfig_path="$1"
    local tegra_prod_defconfig="$(dirname "$defconfig_path")/tegra_prod_defconfig"

    if [[ -f "$tegra_prod_defconfig" ]]; then
        echo "Using NVIDIA tegra_prod_defconfig as bootstrap base."
        sudo cp "$tegra_prod_defconfig" "$defconfig_path"
        return 0
    fi

    echo "Error: Stock NVIDIA defconfig is missing or corrupt, and tegra_prod_defconfig was not found." >&2
    echo "Re-extract kernel_src from public_sources.tbz2, then rerun the kernel build." >&2
    return 1
}

resolve_kernel_defconfig() {
    local defconfig_path="$1"
    local cartken_defconfig=""
    local kb_root=""
    local tmp_defconfig=""

    if [[ -n "$DEFCONFIG_FILE" ]]; then
        if [[ ! -f "$DEFCONFIG_FILE" ]]; then
            echo "Error: --defconfig file not found: $DEFCONFIG_FILE" >&2
            return 1
        fi
        echo "Using explicit defconfig: $DEFCONFIG_FILE"
        sudo cp "$DEFCONFIG_FILE" "$defconfig_path"
        return 0
    fi

    kb_root="$(find_kernel_builder_root || true)"
    if [[ -n "$kb_root" && -f "$kb_root/sources/configs/$PATCH/defconfig" ]]; then
        cartken_defconfig="$kb_root/sources/configs/$PATCH/defconfig"
        echo "Using local cartken defconfig: $cartken_defconfig"
        sudo cp "$cartken_defconfig" "$defconfig_path"
        return 0
    fi

    echo "Trying remote cartken defconfig for JetPack $PATCH..."
    tmp_defconfig="$(mktemp)"
    if sudo wget -q -O "$tmp_defconfig" "https://raw.githubusercontent.com/alxhoff/kernel_builder/refs/heads/master/sources/configs/$PATCH/defconfig" \
        && is_valid_defconfig "$tmp_defconfig"; then
        sudo cp "$tmp_defconfig" "$defconfig_path"
        rm -f "$tmp_defconfig"
        echo "Downloaded cartken defconfig for $PATCH."
        return 0
    fi
    rm -f "$tmp_defconfig"

    if is_valid_defconfig "$defconfig_path"; then
        echo "No cartken defconfig for JetPack $PATCH yet; using stock NVIDIA defconfig in kernel tree."
        echo "After tuning the build, save it to sources/configs/$PATCH/defconfig for future runs."
        return 0
    fi

    echo "No cartken defconfig for JetPack $PATCH yet; restoring stock NVIDIA defconfig."
    restore_stock_nvidia_defconfig "$defconfig_path"
}

defconfig_path="$KERNEL_SRC/arch/arm64/configs/defconfig"
if [[ "$ONLY_INSTALL_ARTIFACTS" != true ]]; then
    resolve_kernel_defconfig "$defconfig_path"
fi

resolve_oot_dtb_src_dir() {
    local kernel_out="$1"
    local candidates=()

    if [[ "$JP_MAJOR" == "7"* ]]; then
        candidates=(
            "$kernel_out/build/nvidia-public/devicetree/generic-dtbs"
            "$kernel_out/kernel-devicetree/generic-dts/dtbs"
        )
    else
        candidates=(
            "$kernel_out/kernel-devicetree/generic-dts/dtbs"
            "$kernel_out/build/nvidia-public/devicetree/generic-dtbs"
        )
    fi

    for dir in "${candidates[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "$dir"
            return 0
        fi
    done
    return 1
}

resolve_built_dtb_path() {
    local src_dir="$1"
    local dtb_name="$2"
    local alt_name=""

    if [[ -f "$src_dir/$dtb_name" ]]; then
        echo "$src_dir/$dtb_name"
        return 0
    fi

    if [[ "$dtb_name" == *-nv.dtb ]]; then
        alt_name="${dtb_name%-nv.dtb}.dtb"
    elif [[ "$dtb_name" == *.dtb ]]; then
        alt_name="${dtb_name%.dtb}-nv.dtb"
    fi
    if [[ -n "$alt_name" && -f "$src_dir/$alt_name" ]]; then
        echo "Info: Using alternate DTB $alt_name instead of $dtb_name." >&2
        echo "$src_dir/$alt_name"
        return 0
    fi

    return 1
}

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
    # JP6/JP7: nvbuild.sh drives the build. LOCALVERSION is passed via env;
    # do not append to defconfig (a prior bug left a 2-line file and broke linking).
    NVBUILD_SCRIPT="$KERNEL_SRC_ROOT/nvbuild.sh"
    if [ ! -f "$NVBUILD_SCRIPT" ]; then
        echo "Error: nvbuild.sh not found at $NVBUILD_SCRIPT"
        exit 1
    fi

    export CROSS_COMPILE
    export ARCH=arm64
    export INSTALL_MOD_PATH="$ROOTFS_ROOT_DIR"
    if [ -n "$LOCALVERSION" ]; then
        export LOCALVERSION
        echo "Building with LOCALVERSION=$LOCALVERSION"
    fi

    KERNEL_OUT_DIR="$KERNEL_SRC_ROOT/kernel_out"
    KERNEL_BUILD_DIR="$KERNEL_OUT_DIR/kernel/$(basename "$KERNEL_SRC")"

    if [[ "$ONLY_INSTALL_ARTIFACTS" != true ]]; then
        pushd "$KERNEL_SRC_ROOT" > /dev/null
        if [[ "$ONLY_OOT_MODULES" == true ]]; then
            if [[ ! -d "$KERNEL_BUILD_DIR" ]]; then
                echo "Error: Existing kernel build output not found at $KERNEL_BUILD_DIR" >&2
                echo "Run a full kernel build first, or omit --only-oot-modules." >&2
                exit 1
            fi
            export KERNEL_HEADERS="$KERNEL_BUILD_DIR"
            echo "Running nvbuild.sh -m to build NVIDIA OOT/display modules only..."
            sudo -E "./nvbuild.sh" -m
            echo "Installing NVIDIA OOT/display modules..."
            sudo -E "./nvbuild.sh" -i -m
        else
            echo "Running nvbuild.sh to build kernel and modules..."
            sudo -E "./nvbuild.sh"
            echo "Running nvbuild.sh to install kernel and modules..."
            sudo -E "./nvbuild.sh" -i
        fi
        popd > /dev/null
    else
        echo "Skipping nvbuild; installing existing kernel_out artifacts only."
    fi

    KERNEL_IMAGE_SRC="$KERNEL_BUILD_DIR/arch/arm64/boot/Image"
    if [[ -n "$DTB_NAME_OVERRIDE" ]]; then
        DTB_NAMES=("$DTB_NAME_OVERRIDE")
    elif [[ "$JP_MAJOR" == "7"* ]]; then
        DTB_NAMES=("tegra234-p3737-0000+p3701-0000.dtb")
    else
        DTB_NAMES=("tegra234-p3737-0000+p3701-0000-nv.dtb")
    fi
    DTB_SRC_DIR="$(resolve_oot_dtb_src_dir "$KERNEL_OUT_DIR" || true)"
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
    KERNEL_DTB_FILE="$KERNEL_DTB_DIR/$DTB_NAME"
    ROOTFS_DTB_FILE="$ROOTFS_DTB_DIR/$DTB_NAME"
    ROOTFS_ABS_DTB_FILE="/boot/dtb/$DTB_NAME"
    DTB_SRC=""

    if [[ -n "$DTB_SRC_DIR" ]]; then
        DTB_SRC="$(resolve_built_dtb_path "$DTB_SRC_DIR" "$DTB_NAME" || true)"
    fi
    if [[ -z "$DTB_SRC" && -n "$KERNEL_OUT_DIR" ]]; then
        DTB_SRC="$(find "$KERNEL_OUT_DIR" -type f -name "$DTB_NAME" 2>/dev/null | head -n 1 || true)"
        if [[ -z "$DTB_SRC" && "$DTB_NAME" != *-nv.dtb ]]; then
            DTB_SRC="$(find "$KERNEL_OUT_DIR" -type f -name "${DTB_NAME%.dtb}-nv.dtb" 2>/dev/null | head -n 1 || true)"
        fi
    fi

    if [[ -n "$DTB_SRC" && -f "$DTB_SRC" ]]; then
        echo "Using built DTB: $DTB_SRC"
        echo "Copying $(basename "$DTB_SRC") to $KERNEL_DTB_FILE..."
        sudo cp -v "$DTB_SRC" "$KERNEL_DTB_FILE"
        echo "Copying $(basename "$DTB_SRC") to $ROOTFS_DTB_FILE..."
        sudo cp -v "$DTB_SRC" "$ROOTFS_DTB_FILE"
    else
        echo "Error: $DTB_NAME not found under kernel_out." >&2
        if [[ -n "$DTB_SRC_DIR" && -d "$DTB_SRC_DIR" ]]; then
            echo "Available AGX Orin DTBs in $DTB_SRC_DIR:" >&2
            ls -1 "$DTB_SRC_DIR"/tegra234-p3737-0000+p3701-0000*.dtb 2>/dev/null >&2 || true
        fi
        exit 1
    fi
done

if grep -q "^[[:space:]]*FDT " "$ROOTFS_EXTLINUX_FILE"; then
    sed -i "s|^[[:space:]]*FDT .*|      FDT ${ROOTFS_ABS_DTB_FILE}|" "$ROOTFS_EXTLINUX_FILE"
else
    sed -i "/^[[:space:]]*LINUX /a \      FDT ${ROOTFS_ABS_DTB_FILE}" "$ROOTFS_EXTLINUX_FILE"
fi

echo "Kernel build completed successfully!"

if [[ "$SKIP_THIRD_PARTY_DRIVERS" == true ]]; then
    echo "Skipping third-party out-of-tree driver build as requested."
elif [ "$BUILD_FLOW" = "jp5" ]; then
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
