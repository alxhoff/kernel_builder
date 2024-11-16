#!/bin/bash

# Wrapper script to clean the Jetson kernel build directory using the clean target.
# This script specifically runs clean for the Jetson kernel.

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
clean_SCRIPT="$SCRIPT_DIR/clean_kernel.sh"

# Run clean_kernel.sh for the "jetson" kernel
"$clean_SCRIPT" --kernel-name jetson "$@"

