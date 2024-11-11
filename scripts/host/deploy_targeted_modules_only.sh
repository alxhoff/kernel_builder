#!/bin/bash

# Script to deploy kernel modules to a Jetson device without building
# Usage: ./deploy_targeted_modules_only.sh [--dry-run]
# Arguments:
#   --dry-run: Optional argument to simulate the process without copying anything to the Jetson device.

set -e  # Exit on any command failure

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
MODULE_DIR="kernels/$KERNEL_NAME/kernel/nvidia/drivers/media/i2c"
KERNEL_VERSION="$(ls kernels/$KERNEL_NAME/modules/lib/modules)"
TARGET_DIR="/lib/modules/$KERNEL_VERSION/kernel/drivers/media/i2c"

# Set up device information
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
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

# Update initramfs if modules were copied
if [ "$DRY_RUN" = false ]; then
  echo "Generating and deploying new initramfs on the target device..."

  # Generate new initramfs on the target device
  initramfs_command="ssh root@$DEVICE_IP 'mkinitramfs -o /tmp/initrd.img-$KERNEL_VERSION $KERNEL_VERSION'"
  echo "Generating new initramfs: $initramfs_command"
  eval $initramfs_command

  # Move new initramfs to /boot
  move_initramfs_command="ssh root@$DEVICE_IP 'mv /tmp/initrd.img-$KERNEL_VERSION /boot/initrd'"
  echo "Moving new initramfs to /boot on target device: $move_initramfs_command"
  eval $move_initramfs_command
fi

echo "Kernel module deploy process complete."

