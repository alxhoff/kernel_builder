#!/bin/bash

set -e  # Exit the script immediately if any command exits with a non-zero status

# Usage: ./build_targeted_modules.sh [<kernel-name> <toolchain-name> <arch> <build-target>]
# Example: ./build_targeted_modules.sh jetson aarch64-buildroot-linux-gnu arm64 clean

# Set default values
DEFAULT_KERNEL_NAME="jetson"
DEFAULT_TOOLCHAIN_NAME="aarch64-buildroot-linux-gnu"
DEFAULT_ARCH="arm64"

# If arguments are provided, use them. Otherwise, use default values.
KERNEL_NAME=${1:-$DEFAULT_KERNEL_NAME}
TOOLCHAIN_NAME=${2:-$DEFAULT_TOOLCHAIN_NAME}
ARCH=${3:-$DEFAULT_ARCH}
BUILD_TARGET=${4:-"modules"}  # Optional build target, default to "modules"

# Set up directories
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_DIR="$SCRIPT_DIR/../kernels/$KERNEL_NAME/kernel"
MODULES_DIR="$SCRIPT_DIR/../kernels/$KERNEL_NAME/modules/lib/modules"
BUILD_DIR="$KERNEL_DIR/nvidia/drivers/media/i2c"

# Get the kernel version from the modules directory
KERNEL_VERSION=$(ls "$MODULES_DIR")

if [ -z "$KERNEL_VERSION" ]; then
  echo "Error: Could not determine the kernel version from $MODULES_DIR"
  exit 1
fi

OUTPUT_DIR="$MODULES_DIR/$KERNEL_VERSION"

# Verify directories
if [ ! -d "$BUILD_DIR" ]; then
  echo "Error: Target build directory $BUILD_DIR does not exist"
  exit 1
fi

# Set CROSS_COMPILE with absolute path
TOOLCHAIN_DIR="$SCRIPT_DIR/../toolchains/$TOOLCHAIN_NAME/bin"
CROSS_COMPILE="$TOOLCHAIN_DIR/$TOOLCHAIN_NAME-"

# Run the make command
echo "Running 'make $BUILD_TARGET' in $BUILD_DIR"
make -C "$KERNEL_DIR/kernel" ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE M=$BUILD_DIR $BUILD_TARGET -j$(nproc)

# Only copy if the build target is "modules" or is empty
if [ "$BUILD_TARGET" = "modules" ] || [ "$BUILD_TARGET" = "" ]; then
  echo "Copying built .ko files to $OUTPUT_DIR"
  find "$BUILD_DIR" -name "*.ko" | while read -r ko_file; do
      # Determine the relative path from BUILD_DIR
      relative_path="${ko_file#$BUILD_DIR/}"
      # Create the corresponding directory inside OUTPUT_DIR
      target_dir="$OUTPUT_DIR/$(dirname "$relative_path")"
      mkdir -p "$target_dir"
      # Copy the .ko file to the corresponding directory inside OUTPUT_DIR
      cp "$ko_file" "$target_dir/"
  done
  echo "Build and copy completed successfully."
else
  echo "Build target was not 'modules', skipping the copy of .ko files."
fi

