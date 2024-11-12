#!/bin/bash

# Display help information
if [[ "$1" == "--help" ]]; then
  echo "probe_camera_controls.sh - Lists all adjustable controls for a specified v4l2 camera device."
  echo
  echo "Usage:"
  echo "  $0 [<device-ip>] <device>"
  echo
  echo "Description:"
  echo "  Connects to the target device via SSH and retrieves a list of all adjustable controls"
  echo "  for the specified camera device using v4l2-ctl."
  echo
  echo "Example:"
  echo "  $0 192.168.1.100 /dev/video0"
  exit 0
fi

# Set the script directory and device IP
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ "$#" -lt 2 ]; then
    echo "Usage: $0 [<device-ip>] <device>"
    exit 1
  fi
  DEVICE_IP=$1
fi

# Shift arguments if device IP was provided
if [ "$DEVICE_IP" == "$1" ]; then
  shift
fi

DEVICE=$1
USERNAME="root"

# List all adjustable controls for the specified camera device
ssh "$USERNAME@$DEVICE_IP" "v4l2-ctl -d '$DEVICE' --list-ctrls-menus"

