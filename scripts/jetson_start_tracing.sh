#!/bin/bash

# Simple script to start tracing events on a Jetson device using kernel_debugger.py
# Usage: ./start_tracing.sh <events> [<device-ip>] [<username>]
# Arguments:
#   <events>        The events to start tracing
#   [<device-ip>]   The IP address of the target Jetson device (optional if device_ip file exists)
#   [<username>]    The username for accessing the Jetson device (optional if device_username file exists, default: "cartken")

# Get the path to the kernel_debugger.py script
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
KERNEL_DEBUGGER_PATH="$SCRIPT_DIR/../kernel_debugger.py"

EVENTS=$1

# Check if device_ip file exists
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <events> [<device-ip>] [<username>]"
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

# Start tracing events on the Jetson device
echo "Starting tracing on the Jetson device at $DEVICE_IP using kernel_debugger.py..."

python3 "$KERNEL_DEBUGGER_PATH" start-tracing --ip "$DEVICE_IP" --user "$USERNAME" --events "$EVENTS"

if [ $? -eq 0 ]; then
  echo "Tracing started successfully on the Jetson device at $DEVICE_IP"
else
  echo "Failed to start tracing on the Jetson device at $DEVICE_IP"
  exit 1
fi

