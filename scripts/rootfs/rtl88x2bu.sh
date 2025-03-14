#!/bin/bash

# Default values
KERNEL_NAME=""
KERNEL_SOURCE=""

# Display help message
show_help() {
    echo "Usage: $0 --kernel-name <name> | --kernel-src <path> [--localversion <version>]"
    echo
    echo "Options:"
    echo "  --kernel-name <name>  Specify the kernel name to use for building the module."
    echo "  --kernel-src <path>   Specify the kernel source path manually."
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
        --kernel-name)
            KERNEL_NAME="$2"
            shift 2
            ;;
        --kernel-src)
            KERNEL_SOURCE="$2/kernel/kernel"
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

# Ensure either --kernel-name or --kernel-src is provided
if [[ -z "$KERNEL_NAME" && -z "$KERNEL_SOURCE" ]]; then
    echo "Error: You must provide either --kernel-name or --kernel-src."
    show_help
elif [[ -n "$KERNEL_NAME" && -n "$KERNEL_SOURCE" ]]; then
    echo "Error: You cannot specify both --kernel-name and --kernel-src."
    show_help
fi

# Resolve script and toolchain paths
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
TOOLCHAIN_PATH=$(realpath "$SCRIPT_DIR/../../toolchains/aarch64-buildroot-linux-gnu/bin/aarch64-buildroot-linux-gnu-")

# Set kernel source path based on the selected option
if [[ -n "$KERNEL_NAME" ]]; then
    KERNEL_SOURCE=$(realpath "$SCRIPT_DIR/../../kernels/$KERNEL_NAME/kernel/kernel")
elif [[ -n "$KERNEL_SOURCE" ]]; then
    KERNEL_SOURCE=$(realpath "$KERNEL_SOURCE")
fi

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

# Cleanup
# echo "Cleaning up temporary files in $TEMP_DIR"
# rm -rf "$TEMP_DIR"

