#!/bin/bash

set -e

# Function to show help
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --kernel-src-root PATH  Path to the kernel source root (required)"
    echo "  --toolchain PATH        Path to the cross-compilation toolchain prefix (required)"
    echo "  --rootfs-root-dir PATH  Path to the rootfs directory (required)"
    echo "  --tegra-dir PATH        Path to the tegra directory (required)"
    echo "  --patch VERSION         The patch version (required)"
    echo "  -h, --help              Show this help message"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel-src-root)
            KERNEL_SRC_ROOT="$2"
            shift 2
            ;;
        --toolchain)
            CROSS_COMPILE="$2"
            shift 2
            ;;
        --rootfs-root-dir)
            ROOTFS_ROOT_DIR="$2"
            shift 2
            ;;
        --tegra-dir)
            TEGRA_DIR="$2"
            shift 2
            ;;
        --patch)
            PATCH="$2"
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

# Validate arguments
if [[ -z "$KERNEL_SRC_ROOT" || -z "$CROSS_COMPILE" || -z "$ROOTFS_ROOT_DIR" || -z "$TEGRA_DIR" || -z "$PATCH" ]]; then
    echo "Error: Missing required arguments."
    show_help
fi

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

ROOTFS_BOOT_DIR="$ROOTFS_ROOT_DIR/boot/"
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
