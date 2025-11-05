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
    echo "  --toolchain-name <name>        Specify the toolchain to use (default: aarch64-buildroot-linux-gnu)."
    echo "  --toolchain-version <version>  Specify the toolchain version to use (default: 9.3)."
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

# Initialize arguments
TOOLCHAIN_NAME_ARG="--toolchain-name aarch64-buildroot-linux-gnu"
TOOLCHAIN_VERSION_ARG="--toolchain-version 9.3"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --toolchain-name)
      if [ -n "$2" ]; then
        TOOLCHAIN_NAME_ARG="--toolchain-name $2"
        shift 2
      else
        echo "Error: --toolchain-name requires a value"
        exit 1
      fi
      ;;
    --toolchain-version)
      if [ -n "$2" ]; then
        TOOLCHAIN_VERSION_ARG="--toolchain-version $2"
        shift 2
      else
        echo "Error: --toolchain-version requires a value"
        exit 1
      fi
      ;;
    *)
      # Assume the first non-option argument is the kernel name
      if [ -z "$KERNEL_NAME" ]; then
        KERNEL_NAME="$1"
        shift
      else
        echo "Unknown parameter: $1"
        exit 1
      fi
      ;;
  esac
done

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_BUILDER_PATH="$SCRIPT_DIR/../kernel_builder.py"

# Compile the kernel with the xconfig target
echo "Running xconfig for kernel: $KERNEL_NAME"
COMMAND="python3 \"$KERNEL_BUILDER_PATH\" compile --kernel-name \"$KERNEL_NAME\" --arch arm64 $TOOLCHAIN_NAME_ARG $TOOLCHAIN_VERSION_ARG --build-target xconfig"

eval $COMMAND
