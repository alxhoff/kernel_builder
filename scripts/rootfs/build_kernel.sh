#!/bin/bash

set -e

TEGRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS_ROOT_DIR="$TEGRA_DIR/rootfs"
TOOLCHAIN_DIR="$TEGRA_DIR/toolchain/bin"
KERNEL_SRC_ROOT="$TEGRA_DIR/kernel_src"
CROSS_COMPILE="$TOOLCHAIN_DIR/aarch64-buildroot-linux-gnu-"
MAKE_ARGS="ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE -j$(nproc)"
MENUCONFIG=false
LOCALVERSION=""
PATCH="5.1.3"
PATCH_SOURCE=false

declare -A JETPACK_L4T_MAP=(
    [5.1.3]=35.5.0
    [5.1.2]=35.4.1
	[5.1.4]=35.6.0
	[5.1.5]=35.6.1
	[6.0DP]=36.2
	[6.2]=36.4.3
)

# Ensure the script is run with sudo
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo."
    exit 1
fi

# Store the original user to run non-root commands
if [ -z "$SUDO_USER" ]; then
    echo "Error: This script must be run using sudo, not as root directly."
    exit 1
fi

# Function to show help
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --patch VERSION   Specify JetPack version (default: $PATCH)"
    echo "  --menuconfig        Open menuconfig before compiling the kernel"
    echo "  --localversion STR  Set the LOCALVERSION for the kernel build"
    echo "  -h, --help          Show this help message"
    exit 0
}

# Parse arguments
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

KERNEL_SRC_DIR_BASE="$TEGRA_DIR/kernel_src/kernel"
# Find the actual kernel source directory, e.g., kernel-jammy-src
KERNEL_SRC_SUBDIR=$(find "$KERNEL_SRC_DIR_BASE" -mindepth 1 -maxdepth 1 -type d -name "kernel*" | head -n 1)
if [ -z "$KERNEL_SRC_SUBDIR" ]; then
    echo "Error: Could not find kernel source subdirectory in $KERNEL_SRC_DIR_BASE"
    exit 1
fi

# For older JetPack, we rename the directory for compatibility with the build process.
# For JetPack 6+, nvbuild.sh expects the original directory name.
if [[ "$PATCH" != "6.0DP" && "$PATCH" != "6.2" ]]; then
    KERNEL_SRC="$KERNEL_SRC_DIR_BASE/kernel"
    if [[ "$KERNEL_SRC_SUBDIR" != "$KERNEL_SRC" ]]; then
        echo "Renaming kernel source directory to $KERNEL_SRC"
        sudo mv "$KERNEL_SRC_SUBDIR" "$KERNEL_SRC"
    fi
else
    KERNEL_SRC="$KERNEL_SRC_SUBDIR"
    echo "Using kernel source at $KERNEL_SRC"
fi

# Validate JetPack version
if [[ -z "${JETPACK_L4T_MAP[$PATCH]}" ]]; then
    echo "Error: Unsupported JetPack version. Use --help to see available versions."
    exit 1
fi

# Check if toolchain is present, otherwise pull it
echo "Checking for toolchain..."
if [ ! -d "$TOOLCHAIN_DIR" ]; then
    echo "Toolchain not found. Cloning..."
    sudo git clone --depth=1 git@gitlab.com:cartken/kernel-os/jetson-linux-toolchain "$TOOLCHAIN_DIR"
    echo "Toolchain cloned successfully."
fi

# Ensure kernel source exists
if [ ! -d "$KERNEL_SRC" ]; then
    echo "Error: Kernel source directory not found at $KERNEL_SRC"
    exit 1
fi

# Reset kernel source to a clean state before applying patches
echo "Checking git status in kernel source..."
# Add the kernel source directory to Git's safe.directory list for the root user
# This is necessary when running git commands as root on directories owned by another user.
sudo git config --global --add safe.directory "$KERNEL_SRC_ROOT"
if [ ! -d "$KERNEL_SRC_ROOT/.git" ]; then
    echo "Initializing git repository for patch management..."
    (cd "$KERNEL_SRC_ROOT" && git init && git config user.name "KernelBuilder" && git config user.email "builder@localhost" && git add . && git commit --no-gpg-sign -m "Initial kernel source")
else
    # Check if there are any commits before attempting to reset
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
    # Check for jq
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is not installed. Please install jq to proceed."
        exit 1
    fi

    echo "Fetching list of patches for $PATCH kernel..."

    # Fetch the list of files and check if curl was successful
    CURL_RESPONSE=$(curl -s -w "%{http_code}" "$GIT_PATCH_URL")
    HTTP_CODE=${CURL_RESPONSE: -3}
    PATCH_LIST=${CURL_RESPONSE:0:-3}

    if [ "$HTTP_CODE" != "200" ]; then
        echo "Error: Failed to retrieve patch list from GitHub (HTTP code: $HTTP_CODE)."
        echo "Response: $PATCH_LIST"
        exit 1
    fi

    # Check if it's a valid JSON array. The GitHub API returns an array for a directory listing.
    # If it's not an array, it's likely an error object (e.g., for a 404), even if the HTTP code was 200 for some reason.
    if ! echo "$PATCH_LIST" | jq -e 'type=="array"' > /dev/null 2>&1; then
        echo "Error: Invalid JSON response from GitHub (not an array)."
        echo "Response: $PATCH_LIST"
        exit 1
    fi

    # Extract URLs, filter out empty lines, and ignore .gitkeep/.gitignore
    echo "$PATCH_LIST" | jq -r '.[] | select(.name != ".gitkeep" and .name != ".gitignore") | .download_url' | grep -v '^$' | while read -r FILE_URL; do
        # Skip null or empty URLs without exiting
        if [[ -z "$FILE_URL" || "$FILE_URL" == "null" ]]; then
            echo "Skipping invalid or empty patch URL."
            continue
        fi

        FILE_NAME=$(basename "$FILE_URL")

        # Ensure we are not downloading unwanted files
        if [[ "$FILE_NAME" == ".gitkeep" || "$FILE_NAME" == ".gitignore" ]]; then
            echo "Skipping $FILE_NAME (not a patch file)."
            continue
        fi

        PATCH_FILE="$TEGRA_DIR/kernel_patches/$FILE_NAME"

        echo "Downloading $FILE_NAME..."
        wget -v --show-progress -O "$PATCH_FILE" "$FILE_URL"

		if [[ -f "$PATCH_FILE" ]]; then
            echo "Applying patch $FILE_NAME..."
            echo "patch -p1 -d "$KERNEL_SRC_ROOT" --batch --forward < "$PATCH_FILE" || echo "Warning: Some hunks failed!""
            patch -p1 -d "$KERNEL_SRC_ROOT" --batch --forward < "$PATCH_FILE" || echo "Warning: Some hunks failed!"
        else
            echo "Error: Patch file $FILE_NAME not found!"
            exit 1
        fi
    done
fi

cd "$KERNEL_SRC"

# Download cartken_defconfig
defconfig_path="$KERNEL_SRC/arch/arm64/configs/defconfig"
echo "Downloading cartken defconfig..."
sudo wget -O "$defconfig_path" "https://raw.githubusercontent.com/alxhoff/kernel_builder/refs/heads/master/configs/$PATCH/defconfig"
echo "cartken_defconfig downloaded successfully."

if [[ "$PATCH" == "6.0DP" || "$PATCH" == "6.2" ]]; then
    echo "Building kernel for JetPack $PATCH using nvbuild.sh..."

    NVBUILD_SCRIPT="$KERNEL_SRC_ROOT/nvbuild.sh"
    if [ ! -f "$NVBUILD_SCRIPT" ]; then
        echo "Error: nvbuild.sh not found at $NVBUILD_SCRIPT"
        exit 1
    fi

    # Set environment variables for nvbuild.sh
    export CROSS_COMPILE
    export ARCH=arm64
    export INSTALL_MOD_PATH="$ROOTFS_ROOT_DIR"

    # nvbuild.sh needs to be run from its containing directory
    pushd "$KERNEL_SRC_ROOT" > /dev/null

    # Build the kernel and modules
    echo "Running nvbuild.sh to build kernel and modules..."
    sudo -E "./nvbuild.sh"

    # Install the kernel and modules
    echo "Running nvbuild.sh to install kernel and modules..."
    sudo -E "./nvbuild.sh" -i

    popd > /dev/null
else
    sudo make -C "$KERNEL_SRC" $MAKE_ARGS mrproper

    # Run menuconfig if requested
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
fi

# Define paths for kernel Image and DTB
KERNEL_IMAGE_SRC="$KERNEL_SRC/arch/arm64/boot/Image"
KERNEL_IMAGE_DEST="$TEGRA_DIR/kernel/"
ROOTFS_BOOT_DIR="$ROOTFS_ROOT_DIR/boot/"

# Define DTBs based on JetPack version
if [[ "$PATCH" == "6.0DP" || "$PATCH" == "6.2" ]]; then
    DTB_NAMES=("tegra234-p3737-0000+p3701-0000.dtb")
else
    DTB_NAMES=(
      "tegra234-p3701-0000-p3737-0000.dtb"
      "tegra234-p3701-0005-p3737-0000.dtb"
      "tegra234-p3701-0004-p3737-0000.dtb"
    )
fi
KERNEL_DTB_DIR="$TEGRA_DIR/kernel/dtb"
ROOTFS_DTB_DIR="$ROOTFS_BOOT_DIR/dtb"
ROOTFS_EXTLINUX_DIR="$ROOTFS_BOOT_DIR/extlinux"
ROOTFS_EXTLINUX_FILE="$ROOTFS_EXTLINUX_DIR/extlinux.conf"

# Ensure destination directories exist
sudo mkdir -p "$KERNEL_IMAGE_DEST"
sudo mkdir -p "$ROOTFS_DTB_DIR"

# Copy kernel Image
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
    DTB_SRC="$KERNEL_SRC/arch/arm64/boot/dts/nvidia/$DTB_NAME"
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

cd $ROOTFS_ROOT_DIR
THIRD_PARTY_DRIVERS="rtl8192eu rtl88x2bu"

echo "Building third party drivers"

for DRIVER in $THIRD_PARTY_DRIVERS; do
	echo "Building and installing $DRIVER"
	LOCALVERSION="-cartken${PATCH}"
	BUILD_SCRIPT="${DRIVER}.sh"
	echo "$TEGRA_DIR/$BUILD_SCRIPT --kernel-src $KERNEL_SRC_ROOT --toolchain $CROSS_COMPILE --localversion $LOCALVERSION"
	$TEGRA_DIR/$BUILD_SCRIPT --kernel-src $KERNEL_SRC_ROOT --toolchain $CROSS_COMPILE --localversion $LOCALVERSION
done

# Extract the kernel version from the Image file
KERNEL_VERSION=$(strings "$ROOTFS_BOOT_DIR/Image" | grep -oP 'Linux version \K[0-9]+\.[0-9]+\.[0-9]+(?:-[\w\d\.]+)?' | head -n 1)

# Ensure kernel version is extracted
if [[ -z "$KERNEL_VERSION" ]]; then
    echo "Error: Failed to extract kernel version from Image"
    exit 1
fi

echo "Detected Kernel Version: $KERNEL_VERSION"

# Define module destination directory
KERNEL_LIB_DIR="$ROOTFS_ROOT_DIR/lib/modules/$KERNEL_VERSION"
MODULE_DEST_DIR="$KERNEL_LIB_DIR/kernel/drivers/net/wireless"

# Ensure the destination directory exists
sudo mkdir -p "$MODULE_DEST_DIR"
cp "$TEGRA_DIR"/*.ko "$MODULE_DEST_DIR"
depmod -b $ROOTFS_ROOT_DIR $KERNEL_VERSION
