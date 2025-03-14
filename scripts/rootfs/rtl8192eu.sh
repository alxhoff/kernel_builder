#!/bin/bash

# Display help message
show_help() {
    echo "Usage: $0 --kernel-name <kernel_name> | --kernel-src <kernel_path> [--localversion <localversion>]"
    echo
    echo "Options:"
    echo "  --kernel-name <kernel_name>   Use the specified kernel name for building the module."
    echo "  --kernel-src <kernel_path>    Use the specified kernel source directory."
    echo "  --localversion <localversion> Optional local version to append to the kernel version string."
    echo
    echo "Description:"
    echo "This script clones the rtl8192eu repository, builds the module for the specified kernel,"
    echo "and copies the resulting .ko file to the script directory."
    exit 0
}

# Ensure at least one argument is provided
if [ "$#" -lt 2 ]; then
    show_help
fi

# Get the script directory first
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# Parse arguments
KERNEL_NAME=""
KERNEL_SOURCE=""
LOCALVERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel-name)
            KERNEL_NAME="$2"
            KERNEL_SOURCE=$(realpath "$SCRIPT_DIR/../../kernels/$KERNEL_NAME/kernel/kernel")
            shift 2
            ;;
        --kernel-src)
            KERNEL_SOURCE=$(realpath "$2/kernel/kernel")  # Use the provided path as is
            shift 2
            ;;
        --localversion)
            LOCALVERSION="$2"
            shift 2
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Ensure one of --kernel-name or --kernel-src was provided
if [ -z "$KERNEL_SOURCE" ]; then
    echo "Error: You must specify either --kernel-name or --kernel-src."
    show_help
fi

TOOLCHAIN_PATH=$(realpath "$SCRIPT_DIR/../../toolchains/aarch64-buildroot-linux-gnu/bin/aarch64-buildroot-linux-gnu-")

# Validate kernel source path
if [ ! -d "$KERNEL_SOURCE" ]; then
    echo "Error: Kernel source directory does not exist: $KERNEL_SOURCE"
    exit 1
fi

# Clone the rtl8192eu repository
TEMP_DIR=$(mktemp -d)
echo "Cloning rtl8192eu repository into $TEMP_DIR"
cd "$TEMP_DIR" || exit 1
git clone https://github.com/clnhub/rtl8192eu-linux.git

if [ $? -ne 0 ]; then
    echo "Error: Failed to clone repository"
    exit 1
fi

cd rtl8192eu-linux || exit 1

# Add obj-m += 8192eu.o to the Makefile
echo "Adding obj-m += 8192eu.o to the Makefile"
echo "obj-m += 8192eu.o" >> Makefile

# Display resolved paths
echo "Using toolchain: $TOOLCHAIN_PATH"
echo "Using kernel source: $KERNEL_SOURCE"
if [ -n "$LOCALVERSION" ]; then
    echo "Using localversion: $LOCALVERSION"
fi

# Compile the module
MAKE_CMD="make ARCH=arm64 CROSS_COMPILE=$TOOLCHAIN_PATH -C $KERNEL_SOURCE M=$(pwd) modules V=1"
if [ -n "$LOCALVERSION" ]; then
    MAKE_CMD="$MAKE_CMD LOCALVERSION=$LOCALVERSION"
fi
echo "Running make command: $MAKE_CMD"
$MAKE_CMD

if [ $? -ne 0 ]; then
    echo "Error: Build failed"
    exit 1
fi

# Copy the compiled module to the script directory
MODULE_FILE="8192eu.ko"
if [ -f "$MODULE_FILE" ]; then
    echo "Copying module $MODULE_FILE to $SCRIPT_DIR"
    cp "$MODULE_FILE" "$SCRIPT_DIR"
    echo "Module copied to $SCRIPT_DIR/$MODULE_FILE"
else
    echo "Error: Module file not found after compilation"
    exit 1
fi

# Cleanup
echo "Cleaning up temporary files in $TEMP_DIR"
rm -rf "$TEMP_DIR"

