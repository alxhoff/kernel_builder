#!/bin/bash

# Example workflow for cleaning a Jetson kernel
# Usage: ./clean_jetson_kernel.sh

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
KERNEL_BUILDER_PATH="$SCRIPT_DIR/../kernel_builder.py"

# Compile the kernel with the clean target
python3 "$KERNEL_BUILDER_PATH" compile --kernel-name jetson --arch arm64 --toolchain-name aarch64-buildroot-linux-gnu --build-target clean
