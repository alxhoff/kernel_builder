#!/bin/bash

# Script to build kernel modules and copy them to a Jetson device
# Usage: ./build_and_deploy_targeted_modules.sh [--dry-run]
# Arguments:
#   --dry-run: Optional argument to simulate the process without copying anything to the Jetson device.

DRY_RUN=false

# Parse arguments
if [ "$#" -eq 1 ]; then
  if [ "$1" == "--dry-run" ]; then
    DRY_RUN=true
  else
    echo "Invalid argument: $1"
    exit 1
  fi
fi

# Set up variables
KERNEL_NAME="jetson"
TOOLCHAIN_NAME="aarch64-buildroot-linux-gnu"
ARCH="arm64"
MODULE_DIR="kernels/$KERNEL_NAME/kernel/nvidia/drivers/media/i2c"
KERNEL_DIR="kernels/$KERNEL_NAME/kernel"
KERNEL_VERSION="$(ls kernels/$KERNEL_NAME/modules/lib/modules)"
TARGET_DIR="/lib/modules/$KERNEL_VERSION/kernel/drivers/media/i2c"

# Build the modules using the build_target_modules.sh script
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
BUILD_SCRIPT_PATH="$SCRIPT_DIR/host/build_targeted_modules.sh"

if [ -f "$BUILD_SCRIPT_PATH" ]; then
  echo "Running build_targeted_modules.sh script"
  "$BUILD_SCRIPT_PATH" "$KERNEL_NAME" "$TOOLCHAIN_NAME" "$ARCH"
else
  echo "Error: build_targeted_modules.sh script not found."
  exit 1
fi

# Set up device information
DEVICE_IP_FILE="$SCRIPT_DIR/device_ip"
DEVICE_USERNAME_FILE="$SCRIPT_DIR/device_username"

if [ -f "$DEVICE_IP_FILE" ]; then
  DEVICE_IP=$(cat "$DEVICE_IP_FILE")
else
  echo "Error: Device IP not found. Please specify it in the device_ip file."
  exit 1
fi

if [ -f "$DEVICE_USERNAME_FILE" ]; then
  DEVICE_USERNAME=$(cat "$DEVICE_USERNAME_FILE")
else
  DEVICE_USERNAME="cartken"
fi

# Check if target_modules.txt file exists
TARGET_MODULES_FILE="$SCRIPT_DIR/host/target_modules.txt"
if [ -f "$TARGET_MODULES_FILE" ]; then
  echo "Using target_modules.txt to determine which modules to copy."
  TARGET_MODULES=$(cat "$TARGET_MODULES_FILE")
else
  echo "No target_modules.txt file found. Copying all modules."
  TARGET_MODULES=$(find "$MODULE_DIR" -name '*.ko' -exec basename {} \;)
fi

# Copy the built modules to the target device
for ko_filename in $TARGET_MODULES; do
  ko_file="$MODULE_DIR/$ko_filename"
  if [ -f "$ko_file" ]; then
    destination="$TARGET_DIR/$ko_filename"

    # Rename existing module on target device, if it exists
    rename_command="ssh root@$DEVICE_IP 'if [ -f $destination ]; then mv $destination ${destination}.previous; fi'"
    echo "Renaming existing module on target device (if any): $rename_command"
    if [ "$DRY_RUN" = false ]; then
      eval $rename_command
    fi

    # Copy the new module to the target device
    copy_command="scp $ko_file root@$DEVICE_IP:$destination"
    echo "Copying module $ko_filename to target device: $copy_command"
    if [ "$DRY_RUN" = false ]; then
      eval $copy_command
    fi
  else
    echo "Warning: Module $ko_filename not found in $MODULE_DIR. Skipping."
  fi

done

echo "Kernel module build and deploy process complete."

