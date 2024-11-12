#!/bin/bash

# Display help information
if [[ "$1" == "--help" ]]; then
  echo "camera_info.sh - Displays detailed information about a specified v4l2 camera device."
  echo
  echo "Usage:"
  echo "  $0 [<device-ip>] <device>"
  echo
  echo "Description:"
  echo "  Connects to the target device via SSH and retrieves detailed information for a given"
  echo "  camera device using v4l2-ctl. This includes device capabilities, supported formats,"
  echo "  and various control options."
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

# Fetch information about the specified camera device
ssh "$USERNAME@$DEVICE_IP" "v4l2-ctl -d '$DEVICE' --all"

