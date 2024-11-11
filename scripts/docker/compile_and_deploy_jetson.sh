#!/bin/bash

# Example workflow for compiling and optionally deploying a Jetson kernel
# Usage: ./compile_and_deploy_jetson.sh [--no-deploy]
# Arguments:
#   --no-deploy  Optional argument to skip deploying the kernel to the device

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [--no-deploy]"
  exit 1
fi

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_BUILDER_PATH="$SCRIPT_DIR/../kernel_builder.py"
KERNEL_DEPLOYER_PATH="$SCRIPT_DIR/../kernel_deployer.py"

# Check if --no-deploy argument is provided
NO_DEPLOY=false
if [ "$#" -eq 1 ]; then
  if [ "$1" == "--no-deploy" ]; then
    NO_DEPLOY=true
  else
    echo "Invalid argument"
    exit 1
  fi
fi

# Read the device IP and username from files, if they exist
DEVICE_IP=""
USERNAME="cartken" # default username

if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(<"$SCRIPT_DIR/device_ip")
fi

if [ -f "$SCRIPT_DIR/device_username" ]; then
  USERNAME=$(<"$SCRIPT_DIR/device_username")
fi

# Compile the kernel
python3 "$KERNEL_BUILDER_PATH" compile --kernel-name jetson --arch arm64 --toolchain-name aarch64-buildroot-linux-gnu --config tegra_defconfig

# Deploy to Jetson device (if not skipped)
if [ "$NO_DEPLOY" == false ]; then
  if [ -z "$DEVICE_IP" ]; then
    echo "Error: Device IP is required to deploy the kernel. Please provide it in the device_ip file."
    exit 1
  fi

  python3 "$KERNEL_DEPLOYER_PATH" deploy-jetson --kernel-name jetson --ip "$DEVICE_IP" --user "$USERNAME"
fi

