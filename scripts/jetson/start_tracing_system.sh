#!/bin/bash

# Script to start tracing all events from a specified system on a Jetson device
# Usage: ./start_tracing_system.sh <system-name> [device-ip] [device-username]

SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_DEBUGGER_PATH="$SCRIPT_DIR/../kernel_debugger.py"

# Get system name as the first argument
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <system-name> [device-ip] [device-username]"
  exit 1
fi

SYSTEM_NAME=$1

# Determine the device IP
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
elif [ -n "$2" ]; then
  DEVICE_IP=$2
else
  echo "Error: Device IP not specified."
  exit 1
fi

# Determine the device username
if [ -f "$SCRIPT_DIR/device_username" ]; then
  DEVICE_USERNAME=$(cat "$SCRIPT_DIR/device_username")
elif [ -n "$3" ]; then
  DEVICE_USERNAME=$3
else
  DEVICE_USERNAME="cartken"  # Default username
fi

# Start tracing all events under the specified system
python3 "$KERNEL_DEBUGGER_PATH" start-tracing --ip "$DEVICE_IP" --user "$DEVICE_USERNAME" --events "$SYSTEM_NAME"

