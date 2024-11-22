#!/bin/bash

# Kernel Error Detection with Function Graph Tracing
# Usage: ./kernel_error_detection.sh [<device-ip>] [--output <file>]

if [[ "$1" == "--help" || -z "$1" ]]; then
  cat << EOF
Usage: ./kernel_error_detection.sh [<device-ip>] [--output <file>]

Description:
  This script monitors the kernel logs for errors (e.g., panics, warnings) and captures
  the last executed functions using function graph tracing.

Parameters:
  <device-ip>       IP address of the target device (e.g., Jetson Orin). Optional if 'device_ip' file exists.
  --output <file>   (Optional) Save the captured logs to a specified file.

Workflow:
  1. Monitors the kernel logs in real-time using `dmesg`.
  2. Captures the function trace log upon detecting errors (e.g., panics, warnings).
  3. Saves the logs to the specified file or displays them in the console.

Examples:
  Detect kernel errors and save logs:
    ./kernel_error_detection.sh 192.168.1.100 --output error_logs.txt

  Detect kernel errors and display logs in real-time:
    ./kernel_error_detection.sh 192.168.1.100
EOF
  exit 0
fi

# Get the device IP
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ -z "$1" ]; then
    echo "Usage: $0 [<device-ip>] [--output <file>]"
    exit 1
  fi
  DEVICE_IP=$1
  shift
fi

TRACE_DIR="/sys/kernel/debug/tracing"
USERNAME="root"
OUTPUT_FILE=""

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --output) OUTPUT_FILE="$2"; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# Monitor kernel logs and capture traces upon errors
echo "Monitoring kernel logs for errors..."
ssh "$USERNAME@$DEVICE_IP" "dmesg -w" | while read -r line; do
  if echo "$line" | grep -qE "WARNING|PANIC|BUG"; then
    echo "Kernel error detected: $line"
    echo "Capturing function graph trace..."
    ssh "$USERNAME@$DEVICE_IP" "cat $TRACE_DIR/trace" > captured_trace.log
    echo "Captured function graph trace saved to captured_trace.log"

    if [ -n "$OUTPUT_FILE" ]; then
      mv captured_trace.log "$OUTPUT_FILE"
      echo "Logs saved to $OUTPUT_FILE"
    else
      cat captured_trace.log
    fi
    break
  fi
done

