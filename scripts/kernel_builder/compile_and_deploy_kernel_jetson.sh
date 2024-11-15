#!/bin/bash

# Script to compile and deploy the Jetson kernel using compile_and_deploy_kernel.sh
# Usage: ./compile_and_deploy_kernel_jetson.sh [OPTIONS]

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
COMPILE_DEPLOY_SCRIPT="$SCRIPT_DIR/compile_and_deploy_kernel.sh"

# Ensure the compile_and_deploy_kernel.sh script exists
if [ ! -f "$COMPILE_DEPLOY_SCRIPT" ]; then
  echo "Error: compile_and_deploy_kernel.sh not found in $SCRIPT_DIR"
  exit 1
fi

# Execute compile_and_deploy_kernel.sh with the kernel name as 'jetson'
"$COMPILE_DEPLOY_SCRIPT" jetson "$@"

