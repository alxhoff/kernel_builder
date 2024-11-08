#!/bin/bash

# Simple script to deploy a compiled kernel to a Jetson device
# Usage: ./deploy_only_jetson.sh <device-ip>
# Arguments:
#   <device-ip>  The IP address of the target Jetson device

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <device-ip>"
  exit 1
fi

DEVICE_IP=$1

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
KERNEL_DEPLOYER_PATH="$SCRIPT_DIR/../kernel_deployer.py"

# Deploy to Jetson device
python3 "$KERNEL_DEPLOYER_PATH" deploy-jetson --kernel-name jetson --ip $DEVICE_IP --user cartken
