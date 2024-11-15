#!/bin/bash

# Script to deploy the Jetson kernel using deploy_kernel.sh
# Usage: ./deploy_kernel_jetson.sh [OPTIONS]

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy_kernel.sh"

# Ensure the deploy_kernel.sh script exists
if [ ! -f "$DEPLOY_SCRIPT" ]; then
  echo "Error: deploy_kernel.sh not found in $SCRIPT_DIR"
  exit 1
fi

# Execute deploy_kernel.sh with the kernel name as 'jetson'
"$DEPLOY_SCRIPT" jetson "$@"

