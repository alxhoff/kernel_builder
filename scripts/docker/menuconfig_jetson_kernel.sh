#!/bin/bash

# Example workflow for running menuconfig for a Jetson kernel
# Usage: ./menuconfig_jetson.sh

SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_BUILDER_PATH="$SCRIPT_DIR/../../kernel_builder.py"

# Compile the kernel with the menuconfig target
python3 "$KERNEL_BUILDER_PATH" compile --kernel-name jetson --arch arm64 --toolchain-name aarch64-buildroot-linux-gnu --build-target menuconfig

