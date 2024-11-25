#!/bin/bash

# Trace all functions in the t194-nvcsi module
# Usage: ./trace_t194-nvcsi.sh [<device-ip>] [--duration <seconds>]

if [[ "$1" == "--help" ]]; then
  cat << EOF
Usage: ./trace_t194-nvcsi.sh [<device-ip>] [--duration <seconds>]

Description:
  This script traces all functions in the 't194-nvcsi' kernel module using function graph tracing.

Parameters:
  <device-ip>       IP address of the target device (e.g., Jetson Orin). Optional if 'device_ip' file exists.
  --duration        (Optional) Specify the tracing duration in seconds.

Workflow:
  1. Reads the device IP from a 'device_ip' file in the script's parent directory, or uses the provided argument.
  2. Adds all functions from the 't194-nvcsi' module to the trace filter.
  3. Starts the function graph tracer.
  4. Stops the tracing either after a duration or upon user confirmation.
  5. Saves the trace log as ./trace_t194-nvcsi.txt.

Examples:
  Trace all functions in 't194-nvcsi' for 10 seconds:
    ./trace_t194-nvcsi.sh 192.168.1.100 --duration 10

  Trace all functions in 't194-nvcsi' until manually stopped:
    ./trace_t194-nvcsi.sh

EOF
  exit 0
fi

SCRIPT_DIR="$(realpath "$(dirname "$0")/../..")"

if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ -z "$1" ]; then
    echo "Usage: $0 [<device-ip>] [--duration <seconds>]"
    exit 1
  fi
  DEVICE_IP=$1
  shift
fi

DURATION=0

# Optional duration
if [[ "$1" == "--duration" && -n "$2" ]]; then
  DURATION=$2
fi

TRACE_DIR="/sys/kernel/debug/tracing"
USERNAME="root"

echo "Adding all functions from module 't194-nvcsi' to trace filter..."
ssh "$USERNAME@$DEVICE_IP" "echo 't194-nvcsi:*' > $TRACE_DIR/set_ftrace_filter"

echo "Starting function graph tracing..."
ssh "$USERNAME@$DEVICE_IP" "echo 'function_graph' > $TRACE_DIR/current_tracer && echo 1 > $TRACE_DIR/tracing_on"

if [ "$DURATION" -gt 0 ]; then
  echo "Tracing for $DURATION seconds..."
  sleep "$DURATION"
fi

echo "Stopping tracing..."
ssh "$USERNAME@$DEVICE_IP" "echo 0 > $TRACE_DIR/tracing_on"

echo "Fetching trace logs..."
ssh "$USERNAME@$DEVICE_IP" "cat $TRACE_DIR/trace" > "./trace_t194-nvcsi.txt"
echo "Trace log saved as ./trace_t194-nvcsi.txt"

