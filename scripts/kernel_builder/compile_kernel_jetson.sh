#!/bin/bash

# Script to compile the Jetson kernel using compile_kernel.sh
# Usage: ./compile_kernel_jetson.sh [OPTIONS]

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
COMPILE_SCRIPT="$SCRIPT_DIR/compile_kernel.sh"

# Ensure the compile_kernel.sh script exists
if [ ! -f "$COMPILE_SCRIPT" ]; then
  echo "Error: compile_kernel.sh not found in $SCRIPT_DIR"
  exit 1
fi

# Execute compile_kernel.sh with the kernel name as 'jetson'
"$COMPILE_SCRIPT" jetson "$@"

