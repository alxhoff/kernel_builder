#!/bin/bash

# Default values
KERNEL_SOURCE=""
TOOLCHAIN_PATH=""

# Display help message
show_help() {
    echo "Usage: $0 --kernel-src <path> --toolchain <path> [--localversion <version>]"
    echo
    echo "Options:"
    echo "  --kernel-src <path>   Specify the kernel source path manually."
    echo "  --toolchain <path>    Specify the toolchain path, including the prefix for compilation."
    echo "  --localversion <ver>  Optional local version to append to the kernel version string."
    echo "  --help                Show this help message and exit."
    echo
    echo "Description:"
    echo "This script clones the rtl88x2bu repository, builds the module for the specified kernel,"
    echo "and copies the resulting .ko file to the script directory."
    exit 0
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel-src)
            KERNEL_SOURCE="$2"
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

# Resolve script and kernel source paths
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
KERNEL_SOURCE=$(realpath "$KERNEL_SOURCE")

# Check if the kernel source directory exists
if [ ! -d "$KERNEL_SOURCE" ]; then
    echo "Error: Kernel source directory does not exist: $KERNEL_SOURCE"
    exit 1
fi

# Clone the rtl88x2bu repository
TEMP_DIR=$(mktemp -d)
echo "Cloning rtl88x2bu repository into $TEMP_DIR"
cd "$TEMP_DIR" || exit 1
git clone https://github.com/cilynx/rtl88x2bu.git

if [ $? -ne 0 ]; then
    echo "Failed to clone repository"
    exit 1
fi

cd rtl88x2bu || exit 1

# Add obj-m += 88x2bu.o to the Makefile
echo "Adding obj-m += 88x2bu.o to the Makefile"
echo "obj-m += 88x2bu.o" >> Makefile

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
    echo "Build failed"
    exit 1
fi

# Copy the compiled module to the script directory
MODULE_FILE="88x2bu.ko"
if [ -f "$MODULE_FILE" ]; then
    echo "Copying module $MODULE_FILE to $SCRIPT_DIR"
    cp "$MODULE_FILE" "$SCRIPT_DIR"
    echo "Module copied to $SCRIPT_DIR/$MODULE_FILE"
else
    echo "Module file not found after compilation"
    exit 1
fi

