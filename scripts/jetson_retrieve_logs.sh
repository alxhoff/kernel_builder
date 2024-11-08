#!/bin/bash

# Simple script to retrieve kernel logs from a Jetson device using kernel_debugger.py
# Usage: ./retrieve_logs.sh <destination-path> [<device-ip>] [<username>]
# Arguments:
#   <destination-path>  Path to save the kernel logs on the local machine
#   [<device-ip>]       The IP address of the target Jetson device (optional if device_ip file exists)
#   [<username>]        The username for accessing the Jetson device (optional if device_username file exists, default: "cartken")

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
KERNEL_DEBUGGER_PATH="$SCRIPT_DIR/../kernel_debugger.py"

DESTINATION_PATH=$1

# Check if device_ip file exists
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <destination-path> [<device-ip>] [<username>]"
    exit 1
  fi
  DEVICE_IP=$2
fi

# Check if device_username file exists
if [ -f "$SCRIPT_DIR/device_username" ]; then
  USERNAME=$(cat "$SCRIPT_DIR/device_username")
else
  if [ "$#" -eq 3 ]; then
    USERNAME=$3
  else
    USERNAME="cartken"
  fi
fi

# Retrieve kernel logs from the Jetson device
echo "Retrieving kernel logs from the Jetson device at $DEVICE_IP using kernel_debugger.py..."

python3 "$KERNEL_DEBUGGER_PATH" retrieve-logs --ip "$DEVICE_IP" --user "$USERNAME" --destination-path "$DESTINATION_PATH"

if [ $? -eq 0 ]; then
  echo "Kernel logs retrieved successfully from the Jetson device at $DEVICE_IP"
else
  echo "Failed to retrieve kernel logs from the Jetson device at $DEVICE_IP"
  exit 1
fi

