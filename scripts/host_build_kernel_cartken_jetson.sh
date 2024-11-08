#!/bin/bash

# Simple script to build the kernel for the Cartken Jetson setup
# Usage: ./build_kernel_host_cartken_jetson.sh [<build-target>]
# Arguments:
#   [<build-target>]   Optional build target (e.g., "clean")

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
BUILD_SCRIPT="$SCRIPT_DIR/build_kernel_host.sh"

KERNEL_NAME="jetson"
TOOLCHAIN_NAME="aarch64-buildroot-linux-gnu"
BUILD_TARGET=${1:-}

# Call the main build script
if [ -z "$BUILD_TARGET" ]; then
  "$BUILD_SCRIPT" "$KERNEL_NAME" "$TOOLCHAIN_NAME"
else
  "$BUILD_SCRIPT" "$KERNEL_NAME" "$TOOLCHAIN_NAME" "$BUILD_TARGET"
fi

