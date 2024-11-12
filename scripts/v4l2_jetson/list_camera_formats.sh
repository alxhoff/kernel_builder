#!/bin/bash

# Display help information
if [[ "$1" == "--help" ]]; then
  echo "list_camera_formats.sh - Lists supported formats for a specified v4l2 camera device."
  echo
  echo "Usage:"
  echo "  $0 [<device-ip>] <device>"
  echo
  echo "Description:"
  echo "  Connects to the specified target device via SSH and retrieves a list of supported"
  echo "  formats for the given camera device using v4l2-ctl. This includes format names, pixel"
  echo "  formats, and frame sizes."
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
DEVICE=$2
USERNAME="root"

# List supported formats for the specified camera device
ssh "$USERNAME@$DEVICE_IP" "v4l2-ctl -d $DEVICE --list-formats-ext"

