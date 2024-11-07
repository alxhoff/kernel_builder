#!/bin/bash

# Example workflow for compiling and flashing a Jetson with a specific kernel
# Usage: ./example_workflow_jetson.sh <git-tag> <device-ip>
# Arguments:
#   <git-tag>    The Git tag to be used for cloning the repositories (e.g., sensing_world_v1)
#   <device-ip>  The IP address of the target Jetson device

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <git-tag> <device-ip>"
  exit 1
fi

GIT_TAG=$1
DEVICE_IP=$2

# Build the Docker image
python3 kernel_builder.py build

# Clone the toolchain
python3 kernel_builder.py clone-toolchain --toolchain-url https://github.com/alxhoff/Jetson-Linux-Toolchain --toolchain-name aarch64-buildroot-linux-gnu --git-tag $GIT_TAG

# Clone the kernel source
python3 kernel_builder.py clone-kernel --kernel-source-url https://github.com/alxhoff/jetson-kernel --kernel-name jetson --git-tag $GIT_TAG

# Clone the overlays
python3 kernel_builder.py clone-overlays --overlays-url https://github.com/alxhoff/jetson-kernel-overlays --kernel-name jetson --git-tag $GIT_TAG

# Clone the device tree hardware
python3 kernel_builder.py clone-device-tree --device-tree-url https://github.com/alxhoff/jetson-device-tree-hardware --kernel-name jetson --git-tag $GIT_TAG

# Compile the kernel
python3 kernel_builder.py compile --kernel-name jetson --arch arm64 --toolchain-name aarch64-buildroot-linux-gnu --config tegra_defconfig

# Deploy to Jetson device
python3 kernel_deployer.py deploy-jetson --kernel-name jetson --ip $DEVICE_IP --user cartken

