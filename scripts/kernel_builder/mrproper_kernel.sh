#!/bin/bash

# Script to clean a kernel build directory using the mrproper target.
# Usage: ./mrproper_kernel.sh [--help] --kernel-name <name> [OPTIONS]
#
# Arguments:
#   --help                 Show this help message and exit.
#   --kernel-name <name>   Specify the name of the kernel to be cleaned (e.g., "jetson").
#   --arch <arch>          Target architecture (default: arm64).
#   --toolchain-name       Name of the toolchain to use (default: aarch64-buildroot-linux-gnu).
#   --dry-run              Optional argument to simulate the mrproper cleaning process without making changes.

# Default values for arguments
KERNEL_NAME=""
ARCH="arm64"
TOOLCHAIN_NAME="aarch64-buildroot-linux-gnu"
TOOLCHAIN_VERSION="9.3"
DRY_RUN=false

# Parse script arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: ./mrproper_kernel.sh --kernel-name <name> [OPTIONS]"
            echo
            echo "Arguments:"
            echo "  --help                 Show this help message and exit."
            echo "  --kernel-name <name>   Specify the name of the kernel to be cleaned (e.g., \"jetson\")."
            echo "  --arch <arch>          Target architecture (default: arm64)."
            echo "  --toolchain-name       Name of the toolchain to use (default: aarch64-buildroot-linux-gnu)."
    echo "  --toolchain-version    Version of the toolchain to use (default: 9.3)."
            echo "  --dry-run              Optional argument to simulate the mrproper cleaning process without making changes."
            echo
            echo "Description:"
            echo "  This script invokes kernel_builder.py to clean a kernel build directory using the mrproper target."
            echo
            echo "Examples:"
            echo "  ./mrproper_kernel.sh --kernel-name jetson"
            echo "  ./mrproper_kernel.sh --kernel-name my_custom_kernel --arch arm64 --toolchain-name aarch64-toolchain --dry-run"
            exit 0
            ;;
        --kernel-name)
            if [ -n "$2" ]; then
                KERNEL_NAME="$2"
                shift 2
            else
                echo "Error: --kernel-name requires a value"
                exit 1
            fi
            ;;
        --arch)
            if [ -n "$2" ]; then
                ARCH="$2"
                shift 2
            else
                echo "Error: --arch requires a value"
                exit 1
            fi
            ;;
        --toolchain-name)
            if [ -n "$2" ]; then
                TOOLCHAIN_NAME="$2"
                shift 2
            else
                echo "Error: --toolchain-name requires a value"
                exit 1
            fi
            ;;
        --toolchain-version)
            if [ -n "$2" ]; then
                TOOLCHAIN_VERSION="$2"
                shift 2
            else
                echo "Error: --toolchain-version requires a value"
                exit 1
            fi
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
done

# Ensure that kernel name is provided
if [ -z "$KERNEL_NAME" ]; then
    echo "Error: --kernel-name argument is required"
    exit 1
fi

# Set up script and kernel builder path
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_BUILDER_PATH="$SCRIPT_DIR/../kernel_builder.py"

# Construct the command to run
COMMAND="python3 \"$KERNEL_BUILDER_PATH\" compile --kernel-name $KERNEL_NAME --arch $ARCH --toolchain-name $TOOLCHAIN_NAME --toolchain-version $TOOLCHAIN_VERSION --build-target mrproper"

if [ "$DRY_RUN" == true ]; then
    COMMAND="$COMMAND --dry-run"
fi

# Execute the command
echo "Running: $COMMAND"
eval $COMMAND

