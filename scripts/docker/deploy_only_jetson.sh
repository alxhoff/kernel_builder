#!/bin/bash

# Simple script to deploy a compiled kernel to a Jetson device
# Usage: ./deploy_only_jetson.sh [--ip <device-ip>] [--user <username>] [--dry-run]
# Arguments:
#   [--ip <device-ip>]  The IP address of the target Jetson device (optional if device_ip file is present)
#   [--user <username>] The username to access the device (optional if device_username file is present)
#   [--dry-run]         Optional argument to simulate the deployment without copying anything to the Jetson device

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_DEPLOYER_PATH="$SCRIPT_DIR/../kernel_deployer.py"

# Default values
USERNAME="cartken"
DEVICE_IP=""
DRY_RUN=false

# Check if device_ip file exists in the script directory
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(<"$SCRIPT_DIR/device_ip")
fi

# Check if device_username file exists in the script directory
if [ -f "$SCRIPT_DIR/device_username" ]; then
  USERNAME=$(<"$SCRIPT_DIR/device_username")
fi

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --ip) DEVICE_IP="$2"; shift ;;
        --user) USERNAME="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Ensure DEVICE_IP is set
if [ -z "$DEVICE_IP" ]; then
  echo "Error: Device IP address must be provided either via --ip argument or 'device_ip' file."
  exit 1
fi

# Deploy to Jetson device
echo "Deploying compiled kernel to the Jetson device at $DEVICE_IP using kernel_deployer.py..."
if [ "$DRY_RUN" = true ]; then
    python3 "$KERNEL_DEPLOYER_PATH" deploy-jetson --kernel-name jetson --ip "$DEVICE_IP" --user "$USERNAME" --dry-run
else
    python3 "$KERNEL_DEPLOYER_PATH" deploy-jetson --kernel-name jetson --ip "$DEVICE_IP" --user "$USERNAME"
fi

# Check if the deployment was successful
if [ $? -ne 0 ]; then
    echo "Failed to deploy the compiled kernel to the Jetson device at $DEVICE_IP"
    exit 1
fi

echo "Kernel successfully deployed to the Jetson device at $DEVICE_IP"

