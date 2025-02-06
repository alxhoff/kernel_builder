#!/bin/bash

# Display help information
if [[ "$1" == "--help" ]]; then
  echo "list_cameras_i2c.sh - Lists all v4l2 camera devices and their I2C bus & addresses."
  echo
  echo "Usage:"
  echo "  $0 [<device-ip>] [<username>]"
  echo
  echo "Description:"
  echo "  Connects to the specified device via SSH and lists all video devices,"
  echo "  extracting their associated I2C bus and addresses."
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

# SSH command to list V4L2 devices and extract I2C bus information
SSH_CMD="ssh $USERNAME@$DEVICE_IP"

echo "=== Listing V4L2 devices with I2C info on $DEVICE_IP ==="
$SSH_CMD 'for dev in /dev/video*; do
    echo "---------------------------------";
    echo "Device: $dev";
    BUS_INFO=$(v4l2-ctl --device="$dev" --all | grep "Bus info" | head -n 1 | awk "{print \$3}");
    I2C_ADDRESS=$(v4l2-ctl --device="$dev" --all | grep "sensor_control_i2c_packet" | awk -F"[][]" "{print \$2}");

    if [[ -n "$BUS_INFO" ]]; then
        echo "I2C Bus: $BUS_INFO";
    else
        echo "I2C Bus: Not Found";
    fi

    if [[ -n "$I2C_ADDRESS" ]]; then
        echo "I2C Address: 0x$(printf "%x\n" $I2C_ADDRESS)";
    else
        echo "I2C Address: Not Found";
    fi
done'

