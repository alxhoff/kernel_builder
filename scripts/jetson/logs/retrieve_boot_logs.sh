#!/bin/bash

# Script to enable persistent logging and retrieve human-readable boot logs
# Usage: ./retrieve_boot_logs.sh <destination-file> [<device-ip>] [<username>]

SCRIPT_DIR="$(realpath "$(dirname "$0")/../..")"
KERNEL_DEBUGGER_PATH="$SCRIPT_DIR/../kernel_debugger.py"

if [[ "$#" -lt 1 ]]; then
  echo "Usage: $0 <destination-file> [<device-ip>] [<username>]"
  echo
  echo "Examples:"
  echo "1. Use default device IP and username from files:"
  echo "   $0 /tmp/boot_logs.txt"
  echo
  echo "2. Specify IP and username manually:"
  echo "   $0 /tmp/boot_logs.txt 192.168.1.10 root"
  echo
  echo "Details:"
  echo "- Reads 'device_ip' and 'device_username' files if they exist."
  echo "- Requires IP and username if files are not found."
  exit 1
fi

DESTINATION_FILE=$1

if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <destination-file> [<device-ip>] [<username>]"
    exit 1
  fi
  DEVICE_IP=$2
fi

if [ -f "$SCRIPT_DIR/device_username" ]; then
  USERNAME=$(cat "$SCRIPT_DIR/device_username")
else
  if [ "$#" -eq 3 ]; then
    USERNAME=$3
  else
    USERNAME="root"
  fi
fi

echo "Enabling persistent logging on the Jetson device at $DEVICE_IP..."
python3 "$KERNEL_DEBUGGER_PATH" enable-persistent-logging --ip "$DEVICE_IP" --user "$USERNAME"

if [ $? -ne 0 ]; then
  echo "Failed to enable persistent logging on the Jetson device at $DEVICE_IP"
  exit 1
fi

echo "Retrieving human-readable boot logs from the Jetson device at $DEVICE_IP..."
python3 "$KERNEL_DEBUGGER_PATH" retrieve-boot-logs --ip "$DEVICE_IP" --user "$USERNAME" --destination-path "$DESTINATION_FILE"

if [ $? -eq 0 ]; then
  echo "Boot logs retrieved successfully and saved to $DESTINATION_FILE"
else
  echo "Failed to retrieve boot logs from the Jetson device at $DEVICE_IP"
  exit 1
fi

