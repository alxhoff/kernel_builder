#!/bin/bash

# Script to clear all logs on a Jetson device
# Usage: ./clear_all_logs.sh [<device-ip>] [<username>]

SCRIPT_DIR="$(realpath "$(dirname "$0")/../..")"

if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ "$#" -lt 1 ]; then
    echo "Usage: $0 [<device-ip>] [<username>]"
    echo
    echo "Examples:"
    echo "1. Use default device IP and username from files:"
    echo "   $0"
    echo
    echo "2. Specify IP and username manually:"
    echo "   $0 192.168.1.10 root"
    echo
    echo "Details:"
    echo "- Reads 'device_ip' and 'device_username' files if they exist."
    echo "- Requires IP and username if files are not found."
    exit 1
  fi
  DEVICE_IP=$1
fi

if [ -f "$SCRIPT_DIR/device_username" ]; then
  USERNAME=$(cat "$SCRIPT_DIR/device_username")
else
  if [ "$#" -eq 2 ]; then
    USERNAME=$2
  else
    USERNAME="root"
  fi
fi

echo "Clearing all logs on the Jetson device at $DEVICE_IP..."

# Command to clear all logs
CLEAR_COMMAND="journalctl --rotate && journalctl --vacuum-time=1s"

# Execute the command on the target device
ssh "$USERNAME@$DEVICE_IP" "$CLEAR_COMMAND"

if [ $? -eq 0 ]; then
  echo "All logs cleared successfully on the Jetson device at $DEVICE_IP."
else
  echo "Failed to clear all logs on the Jetson device at $DEVICE_IP."
  exit 1
fi

