#!/bin/bash

# Real-Time Monitoring for Function Graph Tracing
# Usage: ./real_time_monitor.sh [<device-ip>] [--output <file>]

if [[ "$1" == "--help" || -z "$1" ]]; then
  cat << EOF
Usage: ./real_time_monitor.sh [<device-ip>] [--output <file>]

Description:
  This script streams function graph trace logs in real-time to the console or saves them incrementally to a file.

Parameters:
  <device-ip>       IP address of the target device (e.g., Jetson Orin). Optional if 'device_ip' file exists.
  --output <file>   (Optional) Save the real-time logs to a specified file.

Workflow:
  1. Starts function graph tracing.
  2. Streams the trace logs in real-time to the console or saves them to a file.
  3. Stops tracing upon user interruption (Ctrl+C).

Examples:
  Stream trace logs in real-time:
    ./real_time_monitor.sh 192.168.1.100

  Save real-time logs to a file:
    ./real_time_monitor.sh 192.168.1.100 --output trace_log_live.txt
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

# Start tracing
echo "Starting real-time monitoring..."
ssh "$USERNAME@$DEVICE_IP" "echo 'function_graph' > $TRACE_DIR/current_tracer && echo 1 > $TRACE_DIR/tracing_on"

# Monitor logs in real-time
if [ -n "$OUTPUT_FILE" ]; then
  echo "Saving real-time logs to $OUTPUT_FILE..."
  ssh "$USERNAME@$DEVICE_IP" "tail -f $TRACE_DIR/trace_pipe" > "$OUTPUT_FILE"
else
  echo "Streaming real-time logs to console. Press Ctrl+C to stop."
  ssh "$USERNAME@$DEVICE_IP" "tail -f $TRACE_DIR/trace_pipe"
fi

# Stop tracing when interrupted
trap 'echo "Stopping tracing..."; ssh "$USERNAME@$DEVICE_IP" "echo 0 > $TRACE_DIR/tracing_on"; exit' INT

