#!/bin/bash

# Example workflow for running menuconfig for a Jetson kernel
# Usage: ./menuconfig_jetson.sh

# Compile the kernel with the menuconfig target
python3 kernel_builder.py compile --kernel-name jetson --arch arm64 --toolchain-name aarch64-buildroot-linux-gnu --build-target menuconfig

