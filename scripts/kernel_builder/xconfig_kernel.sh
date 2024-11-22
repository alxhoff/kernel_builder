#!/bin/bash

# Script to run xconfig for a specified kernel
# Usage: ./xconfig_kernel.sh [OPTIONS] <kernel-name>
# Description:
# This script runs the xconfig tool for configuring a specific kernel source tree.
#
# Options:
#   --help               Display this help message with examples.
#
# Examples:
#   1. Run xconfig for the specified kernel:
#      ./xconfig_kernel.sh jetson
#
#   2. Display help message:
#      ./xconfig_kernel.sh --help

# Function to display help message
show_help() {
    echo "Usage: ./xconfig_kernel.sh [OPTIONS] <kernel-name>"
    echo ""
    echo "This script runs xconfig for a specified kernel."
    echo ""
    echo "Options:"
    echo "  --help            Display this help message with examples."
    echo ""
    echo "Examples:"
    echo "  Run xconfig for the 'jetson' kernel:"
    echo "    ./xconfig_kernel.sh jetson"
    echo ""
    echo "  Display this help message:"
    echo "    ./xconfig_kernel.sh --help"
    exit 0
}

# Check if --help is passed or no arguments are provided
if [[ "$#" -eq 0 || "$1" == "--help" ]]; then
    show_help
fi

# Parse the kernel name argument
KERNEL_NAME="$1"

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_BUILDER_PATH="$SCRIPT_DIR/../kernel_builder.py"

# Compile the kernel with the xconfig target
echo "Running xconfig for kernel: $KERNEL_NAME"
COMMAND="python3 \"$KERNEL_BUILDER_PATH\" compile --kernel-name \"$KERNEL_NAME\" --arch arm64 --toolchain-name aarch64-buildroot-linux-gnu --build-target xconfig"

eval $COMMAND

