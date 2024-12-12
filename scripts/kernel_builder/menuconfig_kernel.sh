#!/bin/bash

# Script to run menuconfig for a specified kernel
# Usage: ./menuconfig_kernel.sh [OPTIONS] <kernel-name>
# Description:
# This script runs the menuconfig tool for configuring a specific kernel source tree.
#
# Options:
#   --help               Display this help message with examples.
#
# Examples:
#   1. Run menuconfig for the specified kernel:
#      ./menuconfig_kernel.sh jetson
#
#   2. Display help message:
#      ./menuconfig_kernel.sh --help

# Function to display help message
show_help() {
    echo "Usage: ./menuconfig_kernel.sh [OPTIONS] <kernel-name>"
    echo ""
    echo "This script runs menuconfig for a specified kernel."
    echo ""
    echo "Options:"
    echo "  --help            Display this help message with examples."
    echo ""
    echo "Examples:"
    echo "  Run menuconfig for the 'jetson' kernel:"
    echo "    ./menuconfig_kernel.sh jetson"
    echo ""
    echo "  Display this help message:"
    echo "    ./menuconfig_kernel.sh --help"
    exit 0
}

# Check if --help is passed or no arguments are provided
if [[ "$#" -eq 0 || "$1" == "--help" ]]; then
    show_help
fi

# Parse the kernel name argument
KERNEL_NAME="$1"
shift # Remove the kernel name from the arguments

# Remaining arguments to pass to kernel_builder.py
EXTRA_ARGS="$@"

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_BUILDER_PATH="$SCRIPT_DIR/../kernel_builder.py"

# Compile the kernel with the menuconfig target
echo "Running menuconfig for kernel: $KERNEL_NAME"
COMMAND="python3 \"$KERNEL_BUILDER_PATH\" compile --kernel-name \"$KERNEL_NAME\" --arch arm64 --toolchain-name aarch64-buildroot-linux-gnu --build-target menuconfig $EXTRA_ARGS"

eval $COMMAND

