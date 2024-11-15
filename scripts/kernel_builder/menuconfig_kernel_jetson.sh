#!/bin/bash

# Script to run menuconfig for the Jetson kernel
# Usage: ./menuconfig_kernel_jetson.sh
# Description:
# This script is a shortcut for running menuconfig specifically for the Jetson kernel.
# It invokes menuconfig_kernel.sh with the kernel name 'jetson'.

SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
MENUCONFIG_SCRIPT="$SCRIPT_DIR/menuconfig_kernel.sh"

# Run menuconfig_kernel.sh with 'jetson' as the kernel name argument
"$MENUCONFIG_SCRIPT" jetson

