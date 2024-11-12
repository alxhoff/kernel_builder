#!/bin/bash

# Display help information
if [[ "$1" == "--help" ]]; then
  echo "set_camera_exposure.sh - Sets the exposure level for a specific v4l2 camera device."
  echo
  echo "Usage:"
  echo "  $0 [<device-ip>] <device> <exposure_value>"
  echo
  echo "Description:"
  echo "  Connects to the specified target device via SSH and sets the exposure level for the"
  echo "  given camera device. The exposure value should be an integer, with valid ranges"
  echo "  dependent on the camera model."
  echo
  echo "Example:"
  echo "  $0 192.168.1.100 /dev/video0 100"
  exit 0
fi

# Set the script directory and device IP
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ "$#" -lt 3 ]; then
    echo "Usage: $0 [<device-ip>] <device> <exposure_value>"
    exit 1
  fi
  DEVICE_IP=$1
fi
DEVICE=$2
EXPOSURE=$3
USERNAME="root"

# Set the exposure on the specified camera device
ssh "$USERNAME@$DEVICE_IP" "v4l2-ctl -d $DEVICE --set-ctrl=exposure_absolute=$EXPOSURE"

