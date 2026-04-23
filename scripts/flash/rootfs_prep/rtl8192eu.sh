#!/bin/bash

# Display help message
show_help() {
    echo "Usage: $0 --kernel-src <kernel_path> --toolchain <toolchain_path> [--localversion <localversion>]"
    echo
    echo "Options:"
    echo "  --kernel-src <kernel_path>    Use the specified kernel source directory."
    echo "  --toolchain <toolchain_path>  Specify the toolchain path, including the prefix for compilation."
    echo "  --localversion <localversion> Optional local version to append to the kernel version string."
    echo
    echo "Description:"
    echo "This script clones the rtl8192eu repository, builds the module for the specified kernel,"
    echo "and copies the resulting .ko file to the script directory."
    exit 0
}

# Ensure required arguments are provided
if [ "$#" -lt 4 ]; then
    show_help
fi

# Get the script directory first
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# Parse arguments
KERNEL_SOURCE=""
TOOLCHAIN_PATH=""
LOCALVERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel-src)
            KERNEL_SOURCE=$(realpath "$2")  # Use the provided path as is
            shift 2
            ;;
        --toolchain)
            TOOLCHAIN_PATH=$(realpath "$2")
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

# Ensure required options are provided
if [[ -z "$KERNEL_SOURCE" || -z "$TOOLCHAIN_PATH" ]]; then
    echo "Error: You must provide both --kernel-src and --toolchain options."
    show_help
fi

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

