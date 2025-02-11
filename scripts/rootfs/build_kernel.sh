#!/bin/bash

set -e

TEGRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS_DIR="$TEGRA_DIR/rootfs"
TOOLCHAIN_DIR="$TEGRA_DIR/toolchain/bin"
KERNEL_SRC="$TEGRA_DIR/kernel_src/kernel/kernel-5.10"
CROSS_COMPILE="$TOOLCHAIN_DIR/aarch64-buildroot-linux-gnu-"
MAKE_ARGS="ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE -j$(nproc)"
MENUCONFIG=false
LOCALVERSION=""

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
USER_HOME=$(eval echo ~$SUDO_USER)

# Function to show help
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --menuconfig        Open menuconfig before compiling the kernel"
    echo "  --localversion STR  Set the LOCALVERSION for the kernel build"
    echo "  -h, --help          Show this help message"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
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

# Check if toolchain is present, otherwise pull it
echo "Checking for toolchain..."
if [ ! -d "$TOOLCHAIN_DIR" ]; then
    echo "Toolchain not found. Cloning..."
    sudo -u "$SUDO_USER" git clone --depth=1 git@gitlab.com:cartken/kernel-os/jetson-linux-toolchain "$TOOLCHAIN_DIR"
    echo "Toolchain cloned successfully."
fi

# Ensure kernel source exists
if [ ! -d "$KERNEL_SRC" ]; then
    echo "Error: Kernel source directory not found at $KERNEL_SRC"
    exit 1
fi

cd "$KERNEL_SRC"

# Download cartken_defconfig
defconfig_path="$KERNEL_SRC/arch/arm64/configs/cartken_defconfig"
echo "Checking for cartken_defconfig..."
if [ ! -f "$defconfig_path" ]; then
    echo "Downloading cartken_defconfig..."
    sudo -u "$SUDO_USER" wget -O "$defconfig_path" "https://raw.githubusercontent.com/alxhoff/kernel_builder/refs/heads/master/configs/cartken_defconfig"
    echo "cartken_defconfig downloaded successfully."
fi

# Run menuconfig if requested
if [ "$MENUCONFIG" = true ]; then
    echo "Running menuconfig..."
    sudo -u "$SUDO_USER" make -C "$KERNEL_SRC" $MAKE_ARGS menuconfig
fi

# Compile the kernel as the original user
if [ -n "$LOCALVERSION" ]; then
    echo "Building kernel with LOCALVERSION=$LOCALVERSION..."
    sudo -u "$SUDO_USER" make -C "$KERNEL_SRC" $MAKE_ARGS LOCALVERSION="$LOCALVERSION" tegra_defconfig
    sudo -u "$SUDO_USER" make -C "$KERNEL_SRC" $MAKE_ARGS LOCALVERSION="$LOCALVERSION"

    # Run modules_install as root
    make -C "$KERNEL_SRC" $MAKE_ARGS LOCALVERSION="$LOCALVERSION" modules_install INSTALL_MOD_PATH="$ROOTFS_DIR"
else
    echo "Building kernel using cartken_defconfig..."
    sudo -u "$SUDO_USER" make -C "$KERNEL_SRC" $MAKE_ARGS tegra_defconfig
    sudo -u "$SUDO_USER" make -C "$KERNEL_SRC" $MAKE_ARGS

    # Run modules_install as root
    make -C "$KERNEL_SRC" $MAKE_ARGS modules_install INSTALL_MOD_PATH="$ROOTFS_DIR"
fi

# Define paths for kernel Image and DTB
KERNEL_IMAGE_SRC="$KERNEL_SRC/arch/arm64/boot/Image"
KERNEL_IMAGE_DEST="$TEGRA_DIR/kernel/"
KERNEL_IMAGE_ROOTFS="$ROOTFS_DIR/boot/"

DTB_SRC="$KERNEL_SRC/arch/arm64/boot/dts/nvidia/tegra234-p3701-0000-p3737-0000.dtb"
DTB_DEST="$TEGRA_DIR/kernel/dtb/"
DTB_ROOTFS="$ROOTFS_DIR/boot/dtb/"

# Ensure destination directories exist
sudo mkdir -p "$KERNEL_IMAGE_DEST"
sudo mkdir -p "$KERNEL_IMAGE_ROOTFS"
sudo mkdir -p "$DTB_DEST"
sudo mkdir -p "$DTB_ROOTFS"

# Copy kernel Image
if [ -f "$KERNEL_IMAGE_SRC" ]; then
    echo "Copying kernel Image to $KERNEL_IMAGE_DEST..."
    sudo cp -v "$KERNEL_IMAGE_SRC" "$KERNEL_IMAGE_DEST"

    echo "Copying kernel Image to $KERNEL_IMAGE_ROOTFS..."
    sudo cp -v "$KERNEL_IMAGE_SRC" "$KERNEL_IMAGE_ROOTFS"
else
    echo "Error: Kernel Image not found at $KERNEL_IMAGE_SRC"
    exit 1
fi

# Copy DTB file
if [ -f "$DTB_SRC" ]; then
    echo "Copying DTB file to $DTB_DEST..."
    sudo cp -v "$DTB_SRC" "$DTB_DEST"

    echo "Copying DTB file to $DTB_ROOTFS..."
    sudo cp -v "$DTB_SRC" "$DTB_ROOTFS"
else
    echo "Error: DTB file not found at $DTB_SRC"
    exit 1
fi

echo "Kernel build completed successfully!"

