#!/bin/bash

# Example workflow for compiling and optionally deploying a Jetson kernel
# Usage: ./compile_and_deploy_jetson.sh [<device-ip>] [--no-deploy]
# Arguments:
#   <device-ip>  The IP address of the target Jetson device (optional if --no-deploy is specified)
#   --no-deploy  Optional argument to skip deploying the kernel to the device

if [ "$#" -lt 0 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 [<device-ip>] [--no-deploy]"
  exit 1
fi

NO_DEPLOY=false
DEVICE_IP=""

if [ "$#" -eq 1 ]; then
  if [ "$1" == "--no-deploy" ]; then
    NO_DEPLOY=true
  else
    DEVICE_IP=$1
  fi
fi

if [ "$#" -eq 2 ]; then
  if [ "$2" == "--no-deploy" ]; then
    NO_DEPLOY=true
    DEVICE_IP=$1
  else
    echo "Invalid arguments"
    exit 1
  fi
fi

# Compile the kernel
python3 kernel_builder.py compile --kernel-name jetson --arch arm64 --toolchain-name aarch64-buildroot-linux-gnu --config tegra_defconfig

# Deploy to Jetson device (if not skipped)
if [ "$NO_DEPLOY" == false ]; then
  if [ -z "$DEVICE_IP" ]; then
    echo "Error: Device IP is required unless --no-deploy is specified."
    exit 1
  fi
  python3 kernel_deployer.py deploy-jetson --kernel-name jetson --ip $DEVICE_IP --user cartken
fi

