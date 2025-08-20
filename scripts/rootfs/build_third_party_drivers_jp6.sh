#!/bin/bash

set -e

# Function to show help
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --kernel-src PATH         Path to the kernel source (required)"
    echo "  --kernel-out-dir PATH     Path to the kernel output directory (required)"
    echo "  --toolchain PATH          Path to the cross-compilation toolchain prefix (required)"
    echo "  --rootfs-root-dir PATH    Path to the rootfs directory (required)"
    echo "  --tegra-dir PATH          Path to the tegra directory (required)"
    echo "  --patch VERSION           The patch version (required)"
    echo "  --localversion STR        The local version string (required)"
    echo "  -h, --help                Show this help message"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel-src)
            KERNEL_SRC="$2"
            shift 2
            ;;
        --kernel-out-dir)
            KERNEL_OUT_DIR="$2"
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

# Validate arguments
if [[ -z "$KERNEL_SRC" || -z "$KERNEL_OUT_DIR" || -z "$CROSS_COMPILE" || -z "$ROOTFS_ROOT_DIR" || -z "$TEGRA_DIR" || -z "$PATCH" || -z "$LOCALVERSION" ]]; then
    echo "Error: Missing required arguments."
    show_help
fi

cd "$ROOTFS_ROOT_DIR"

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

THIRD_PARTY_DRIVERS="rtl8192eu rtl88x2bu"

echo "Building third party drivers for JetPack 6+"

for DRIVER in $THIRD_PARTY_DRIVERS; do
    echo "Building and installing $DRIVER"
    
    TEMP_DIR=$(mktemp -d)
    
    if [ "$DRIVER" == "rtl8192eu" ]; then
        echo "Cloning rtl8192eu repository into $TEMP_DIR"
        git clone https://github.com/clnhub/rtl8192eu-linux.git "$TEMP_DIR/rtl8192eu-linux"
        cd "$TEMP_DIR/rtl8192eu-linux"
        echo "obj-m += 8192eu.o" >> Makefile
        MODULE_FILE="8192eu.ko"
    elif [ "$DRIVER" == "rtl88x2bu" ]; then
        echo "Cloning rtl88x2bu repository into $TEMP_DIR"
        git clone https://github.com/cilynx/rtl88x2bu.git "$TEMP_DIR/rtl88x2bu"
        cd "$TEMP_DIR/rtl88x2bu"
        echo "obj-m += 88x2bu.o" >> Makefile
        MODULE_FILE="88x2bu.ko"
    fi

    MAKE_CMD="make ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE -C $KERNEL_SRC O=$KERNEL_OUT_DIR M=$(pwd) modules V=1 LOCALVERSION=$LOCALVERSION"
    echo "Running make command: $MAKE_CMD"
    $MAKE_CMD

    if [ $? -ne 0 ]; then
        echo "Error: Build failed for $DRIVER"
        exit 1
    fi

    if [ -f "$MODULE_FILE" ]; then
        echo "Copying module $MODULE_FILE to $MODULE_DEST_DIR"
        sudo cp "$MODULE_FILE" "$MODULE_DEST_DIR"
        echo "Module copied to $MODULE_DEST_DIR/$MODULE_FILE"
    else
        echo "Error: Module file not found after compilation for $DRIVER"
        exit 1
    fi

    cd "$ROOTFS_ROOT_DIR"
    rm -rf "$TEMP_DIR"
done

depmod -b "$ROOTFS_ROOT_DIR" "$KERNEL_VERSION"
