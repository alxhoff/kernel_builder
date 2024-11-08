#!/bin/bash

# Simple script to record a trace on a Jetson device using kernel_debugger.py
# Usage: ./record_trace.sh <trace-options> [<duration>] [<device-ip>] [<username>]
# Arguments:
#   <trace-options>  Options for trace-cmd record
#   [<duration>]     Duration for recording the trace (optional)
#   [<device-ip>]    The IP address of the target Jetson device (optional if device_ip file exists)
#   [<username>]     The username for accessing the Jetson device (optional if device_username file exists, default: "cartken")

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
KERNEL_DEBUGGER_PATH="$SCRIPT_DIR/../kernel_debugger.py"

TRACE_OPTIONS=$1
DURATION=$2

# Check if device_ip file exists
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <trace-options> [<duration>] [<device-ip>] [<username>]"
    exit 1
  fi
  DEVICE_IP=$3
fi

# Check if device_username file exists
if [ -f "$SCRIPT_DIR/device_username" ]; then
  USERNAME=$(cat "$SCRIPT_DIR/device_username")
else
  if [ "$#" -eq 4 ]; then
    USERNAME=$4
  else
    USERNAME="cartken"
  fi
fi

# Record trace on the Jetson device
echo "Recording trace on the Jetson device at $DEVICE_IP using kernel_debugger.py..."

if [ -z "$DURATION" ]; then
  python3 "$KERNEL_DEBUGGER_PATH" record-trace --ip "$DEVICE_IP" --user "$USERNAME" --trace-options "$TRACE_OPTIONS"
else
  python3 "$KERNEL_DEBUGGER_PATH" record-trace --ip "$DEVICE_IP" --user "$USERNAME" --trace-options "$TRACE_OPTIONS" --duration "$DURATION"
fi

if [ $? -eq 0 ]; then
  echo "Trace recorded successfully on the Jetson device at $DEVICE_IP"
else
  echo "Failed to record trace on the Jetson device at $DEVICE_IP"
  exit 1
fi

