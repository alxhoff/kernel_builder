#!/bin/bash

# Display help information
if [[ "$1" == "--help" ]]; then
  echo "list_cameras.sh - Lists all v4l2 camera devices connected to the target device."
  echo
  echo "Usage:"
  echo "  $0 [<device-ip>] [<username>]"
  echo
  echo "Description:"
  echo "  Connects to the specified device via SSH and uses v4l2-ctl to list all video devices."
  echo "  This is useful for identifying the available camera devices and their /dev nodes."
  echo
  echo "Example:"
  echo "  $0 192.168.1.100 root"
  exit 0
fi

# Set the script directory and device IP
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ "$#" -lt 1 ]; then
    echo "Usage: $0 [<device-ip>] [<username>]"
    exit 1
  fi
  DEVICE_IP=$1
fi
USERNAME="root"

# List all v4l2 devices
ssh "$USERNAME@$DEVICE_IP" 'v4l2-ctl --list-devices'

