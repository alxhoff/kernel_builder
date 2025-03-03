#!/bin/bash

# Simple script to list the kernel modules loaded on a Jetson device using kernel_debugger.py
# Usage: ./list_kernel_modules.sh [<device-ip>] [<username>]
# Arguments:
#   [<device-ip>]   The IP address of the target Jetson device (optional if device_ip file exists)
#   [<username>]    The username for accessing the Jetson device (optional if device_username file exists, default: "cartken")

# Get the path to the kernel_debugger.py script
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_DEBUGGER_PATH="$SCRIPT_DIR/../kernel_debugger.py"

# Check if device_ip file exists
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ "$#" -lt 1 ]; then
    echo "Usage: $0 [<device-ip>] [<username>]"
    exit 1
  fi
  DEVICE_IP=$1
fi

# Check if device_username file exists
if [ -f "$SCRIPT_DIR/device_username" ]; then
  USERNAME=$(cat "$SCRIPT_DIR/device_username")
else
  if [ "$#" -eq 2 ]; then
    USERNAME=$2
  else
    USERNAME="cartken"
  fi
fi

# List kernel modules on the Jetson device
echo "Listing kernel modules loaded on the Jetson device at $DEVICE_IP using kernel_debugger.py..."

python3 "$KERNEL_DEBUGGER_PATH" list-modules --ip "$DEVICE_IP" --user "$USERNAME"

if [ $? -eq 0 ]; then
  echo "Kernel modules listed successfully on the Jetson device at $DEVICE_IP"
else
  echo "Failed to list kernel modules on the Jetson device at $DEVICE_IP"
  exit 1
fi

