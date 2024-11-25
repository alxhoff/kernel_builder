#!/bin/bash

# Generic script to trace a specific function
# Usage: ./trace_function.sh [<device-ip>] <function-name> [--duration <seconds>]

DEFAULT_DURATION=30

if [[ "$1" == "--help" ]]; then
  cat << EOF
Usage: ./trace_function.sh [<device-ip>] <function-name> [--duration <seconds>]

Description:
  This script traces a specific kernel function using function graph tracing.

Parameters:
  <device-ip>       IP address of the target device (e.g., Jetson Orin). Optional if 'device_ip' file exists.
  <function-name>   Name of the function to trace.
  --duration        (Optional) Specify the tracing duration in seconds. Defaults to 30 seconds.

Workflow:
  1. Reads the device IP from a 'device_ip' file in the script's parent directory, or uses the provided argument.
  2. Adds the specified function to the ftrace filter.
  3. Starts the function graph tracer.
  4. Stops the tracing either after a duration or upon user confirmation.
  5. Saves the trace log as ./trace_<function-name>.txt.

Examples:
  Trace function 'vi_capture_control_message' for 30 seconds:
    ./trace_function.sh vi_capture_control_message

  Trace function 'nvcsi_start' for 60 seconds:
    ./trace_function.sh 192.168.1.100 nvcsi_start --duration 60
EOF
  exit 0
fi

SCRIPT_DIR="$(realpath "$(dirname "$0")/../..")"

if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ -z "$1" ]; then
    echo "Usage: $0 [<device-ip>] <function-name> [--duration <seconds>]"
    exit 1
  fi
  DEVICE_IP=$1
  shift
fi

FUNCTION_NAME="$1"
DURATION=$DEFAULT_DURATION

if [ -z "$FUNCTION_NAME" ]; then
  echo "Error: <function-name> is required."
  echo "Usage: $0 [<device-ip>] <function-name> [--duration <seconds>]"
  exit 1
fi

# Optional duration
if [[ "$2" == "--duration" && -n "$3" ]]; then
  DURATION=$3
fi

TRACE_DIR="/sys/kernel/debug/tracing"
USERNAME="root"

echo "Clearing all previous filters..."
ssh "$USERNAME@$DEVICE_IP" "echo '' > $TRACE_DIR/set_ftrace_filter"

echo "Adding function '$FUNCTION_NAME' to trace filter..."
ssh "$USERNAME@$DEVICE_IP" "echo '$FUNCTION_NAME' > $TRACE_DIR/set_ftrace_filter"

echo "Starting function graph tracing..."
ssh "$USERNAME@$DEVICE_IP" "echo 'function_graph' > $TRACE_DIR/current_tracer && echo 1 > $TRACE_DIR/tracing_on"

if [ "$DURATION" -gt 0 ]; then
  echo "Tracing for $DURATION seconds..."
  sleep "$DURATION"
fi

echo "Stopping tracing..."
ssh "$USERNAME@$DEVICE_IP" "echo 0 > $TRACE_DIR/tracing_on"

echo "Fetching trace logs..."
ssh "$USERNAME@$DEVICE_IP" "cat $TRACE_DIR/trace" > "./trace_${FUNCTION_NAME}.txt"
echo "Trace log saved as ./trace_${FUNCTION_NAME}.txt"

