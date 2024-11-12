#!/bin/bash

# Display help information
if [[ "$1" == "--help" ]]; then
  echo "camera_info_all.sh - Displays detailed information for all connected v4l2 camera devices."
  echo
  echo "Usage:"
  echo "  $0 [<device-ip>] [<username>]"
  echo
  echo "Description:"
  echo "  Connects to the target device via SSH, lists all available v4l2 camera devices, and"
  echo "  retrieves detailed information for each device, including device capabilities and"
  echo "  current metadata (e.g., current exposure setting if available)."
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

# List all video devices and gather information
ssh "$USERNAME@$DEVICE_IP" '
for DEVICE in /dev/video*; do
  if v4l2-ctl -d "$DEVICE" --all &>/dev/null; then
    echo "=========================================="
    echo "Device: $DEVICE"
    echo "------------------------------------------"
    v4l2-ctl -d "$DEVICE" --all

    # Fetch and display current metadata such as exposure
    CURRENT_EXPOSURE=$(v4l2-ctl -d "$DEVICE" --get-ctrl=exposure_absolute 2>/dev/null)
    if [[ -n "$CURRENT_EXPOSURE" ]]; then
      echo "Current Exposure: $CURRENT_EXPOSURE"
    else
      echo "Current Exposure: Not available"
    fi
    echo "=========================================="
    echo
  fi
done
'

