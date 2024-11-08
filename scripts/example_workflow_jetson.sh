#!/bin/bash

# Example workflow for compiling and flashing a Jetson with a specific kernel
# Usage: ./example_workflow_jetson.sh <git-tag> [<device-ip>] [--no-deploy]
# Arguments:
#   <git-tag>    The Git tag to be used for cloning the repositories (e.g., sensing_world_v1)
#   <device-ip>  The IP address of the target Jetson device (optional if --no-deploy is specified)
#   --no-deploy  Optional argument to skip deploying the kernel to the device

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
  echo "Usage: $0 <git-tag> [<device-ip>] [--no-deploy]"
  exit 1
fi

GIT_TAG=$1
NO_DEPLOY=false
DEVICE_IP=""

if [ "$#" -eq 2 ]; then
  if [ "$2" == "--no-deploy" ]; then
    NO_DEPLOY=true
  else
    DEVICE_IP=$2
  fi
fi

if [ "$#" -eq 3 ]; then
  if [ "$3" == "--no-deploy" ]; then
    NO_DEPLOY=true
    DEVICE_IP=$2
  else
    echo "Invalid arguments"
    exit 1
  fi
fi

# Build the Docker image
python3 ../kernel_builder.py build

# Clone the toolchain
python3 ../kernel_builder.py clone-toolchain --toolchain-url https://github.com/alxhoff/Jetson-Linux-Toolchain --toolchain-name aarch64-buildroot-linux-gnu --git-tag $GIT_TAG

# Clone the kernel source
python3 ../kernel_builder.py clone-kernel --kernel-source-url https://github.com/alxhoff/jetson-kernel --kernel-name jetson --git-tag $GIT_TAG

# Clone the overlays
python3 ../kernel_builder.py clone-overlays --overlays-url https://github.com/alxhoff/jetson-kernel-overlays --kernel-name jetson --git-tag $GIT_TAG

# Clone the device tree hardware
python3 ../kernel_builder.py clone-device-tree --device-tree-url https://github.com/alxhoff/jetson-device-tree-hardware --kernel-name jetson --git-tag $GIT_TAG

# Compile the kernel
python3 ../kernel_builder.py compile --kernel-name jetson --arch arm64 --toolchain-name aarch64-buildroot-linux-gnu --config tegra_defconfig

# Deploy to Jetson device (if not skipped)
if [ "$NO_DEPLOY" == false ]; then
  if [ -z "$DEVICE_IP" ]; then
    echo "Error: Device IP is required unless --no-deploy is specified."
    exit 1
  fi
  python3 ../kernel_deployer.py deploy-jetson --kernel-name jetson --ip $DEVICE_IP --user cartken
fi

