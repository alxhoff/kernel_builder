#!/bin/bash

# Example workflow for compiling a Jetson kernel
# Usage: ./compile_jetson.sh

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_BUILDER_PATH="$SCRIPT_DIR/../kernel_builder.py"

# Create a LOCALVERSION string that includes "cartken_" and the current date and time
LOCALVERSION="cartken_$(date +%Y_%m_%d__%H_%M)"

# Compile the kernel with the default target (kernel)
python3 "$KERNEL_BUILDER_PATH" compile --kernel-name jetson --arch arm64 --toolchain-name aarch64-buildroot-linux-gnu --localversion "$LOCALVERSION"

