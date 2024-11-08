#!/bin/bash

# Simple script to build the kernel on the host machine
# Usage: ./build_kernel_host.sh <kernel-name> <toolchain-name> [<build-target>]
# Arguments:
#   <kernel-name>      The name of the kernel subfolder (e.g., "jetson")
#   <toolchain-name>   The name of the toolchain to use (e.g., "aarch64-buildroot-linux-gnu")
#   [<build-target>]   Optional build target (e.g., "clean")

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <kernel-name> <toolchain-name> [<build-target>]"
  exit 1
fi

KERNEL_NAME=$1
TOOLCHAIN_NAME=$2
BUILD_TARGET=${3:-}

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
KERNEL_DIR="$SCRIPT_DIR/../kernels/$KERNEL_NAME/kernel/kernel"
TOOLCHAIN_PATH="$SCRIPT_DIR/../toolchains/$TOOLCHAIN_NAME/bin/$TOOLCHAIN_NAME-"

# Build the kernel
echo "Building the kernel for $KERNEL_NAME with toolchain $TOOLCHAIN_NAME..."

if [ -z "$BUILD_TARGET" ]; then
  COMMAND="make -C $KERNEL_DIR ARCH=arm64 -j$(nproc) CROSS_COMPILE=$TOOLCHAIN_PATH"
else
  COMMAND="make -C $KERNEL_DIR ARCH=arm64 -j$(nproc) CROSS_COMPILE=$TOOLCHAIN_PATH $BUILD_TARGET"
fi

echo "Running command: $COMMAND"

# Run the build command
eval $COMMAND

if [ $? -eq 0 ]; then
  echo "Kernel build completed successfully"
else
  echo "Kernel build failed"
  exit 1
fi

