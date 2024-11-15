#!/bin/bash

# Wrapper script to clean the Jetson kernel build directory using the mrproper target.
# This script specifically runs mrproper for the Jetson kernel.

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
MRPROPER_SCRIPT="$SCRIPT_DIR/mrproper_kernel.sh"

# Run mrproper_kernel.sh for the "jetson" kernel
"$MRPROPER_SCRIPT" --kernel-name jetson "$@"

