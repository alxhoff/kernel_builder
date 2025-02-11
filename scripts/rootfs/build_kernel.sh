#!/bin/bash

set -e

TEGRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLCHAIN_DIR="$TEGRA_DIR/toolchain/bin"
KERNEL_SRC="$TEGRA_DIR/kernel_src/kernel/kernel-5.10"
CROSS_COMPILE="$TOOLCHAIN_DIR/bin/aarch64-buildroot-linux-gnu-"
MAKE_ARGS="ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE -j$(nproc)"
MENUCONFIG=false
LOCALVERSION=""

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
    git clone --depth=1 git@gitlab.com:cartken/kernel-os/jetson-linux-toolchain "$TOOLCHAIN_DIR"
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
    wget -O "$defconfig_path" "https://raw.githubusercontent.com/alxhoff/kernel_builder/refs/heads/master/configs/cartken_defconfig"
    echo "cartken_defconfig downloaded successfully."
fi

# Run menuconfig if requested
if [ "$MENUCONFIG" = true ]; then
    echo "Running menuconfig..."
    echo "Executing: make -C "$KERNEL_SRC" $MAKE_ARGS menuconfig"
    make -C "$KERNEL_SRC" $MAKE_ARGS menuconfig
fi

# Compile the kernel
if [ -n "$LOCALVERSION" ]; then
    echo "Building kernel with LOCALVERSION=$LOCALVERSION..."
    echo "Executing: make -C "$KERNEL_SRC" $MAKE_ARGS LOCALVERSION=\"$LOCALVERSION\" cartken_defconfig"
    make -C "$KERNEL_SRC" $MAKE_ARGS LOCALVERSION="$LOCALVERSION" cartken_defconfig
    echo "Executing: make -C "$KERNEL_SRC" $MAKE_ARGS LOCALVERSION=\"$LOCALVERSION\""
    make -C "$KERNEL_SRC" $MAKE_ARGS LOCALVERSION="$LOCALVERSION"
else
    echo "Building kernel using cartken_defconfig..."
    echo "Executing: make -C "$KERNEL_SRC" $MAKE_ARGS tegra_defconfig"
    make -C "$KERNEL_SRC" $MAKE_ARGS cartken_defconfig
    echo "Executing: make -C "$KERNEL_SRC" $MAKE_ARGS"
    make -C "$KERNEL_SRC" $MAKE_ARGS
fi

echo "Kernel build completed successfully!"

