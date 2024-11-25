#!/bin/bash

# Generic script to trace all functions in a specified kernel module
# Usage: ./trace_module.sh [<device-ip>] <module-name> [--duration <seconds>]

if [[ "$1" == "--help" ]]; then
  cat << EOF
Usage: ./trace_module.sh [<device-ip>] <module-name> [--duration <seconds>]

Description:
  This script traces all functions in the specified kernel module using function graph tracing.

Parameters:
  <device-ip>       IP address of the target device (e.g., Jetson Orin). Optional if 'device_ip' file exists.
  <module-name>     Name of the kernel module to trace.
  --duration        (Optional) Specify the tracing duration in seconds.

Workflow:
  1. Reads the device IP from a 'device_ip' file in the script's parent directory, or uses the provided argument.
  2. Adds all functions from the specified module to the trace filter.
  3. Starts the function graph tracer.
  4. Stops the tracing either after a duration or upon user confirmation.
  5. Saves the trace log as ./trace_<module-name>.txt.

Examples:
  Trace all functions in 'max9295' for 10 seconds:
    ./trace_module.sh 192.168.1.100 max9295 --duration 10

  Trace all functions in 'd4xx' until manually stopped:
    ./trace_module.sh d4xx
EOF
  exit 0
fi

SCRIPT_DIR="$(realpath "$(dirname "$0")/../..")"

if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ -z "$1" ]; then
    echo "Usage: $0 [<device-ip>] <module-name> [--duration <seconds>]"
    exit 1
  fi
  DEVICE_IP=$1
  shift
fi

MODULE_NAME="$1"
DURATION=0

if [ -z "$MODULE_NAME" ]; then
  echo "Error: <module-name> is required."
  echo "Usage: $0 [<device-ip>] <module-name> [--duration <seconds>]"
  exit 1
fi

# Optional duration
if [[ "$2" == "--duration" && -n "$3" ]]; then
  DURATION=$3
fi

TRACE_DIR="/sys/kernel/debug/tracing"
USERNAME="root"

echo "Adding all functions from module '$MODULE_NAME' to trace filter..."
ssh "$USERNAME@$DEVICE_IP" "echo '${MODULE_NAME}:*' > $TRACE_DIR/set_ftrace_filter"

echo "Starting function graph tracing..."
ssh "$USERNAME@$DEVICE_IP" "echo 'function_graph' > $TRACE_DIR/current_tracer && echo 1 > $TRACE_DIR/tracing_on"

if [ "$DURATION" -gt 0 ]; then
  echo "Tracing for $DURATION seconds..."
  sleep "$DURATION"
fi

echo "Stopping tracing..."
ssh "$USERNAME@$DEVICE_IP" "echo 0 > $TRACE_DIR/tracing_on"

echo "Fetching trace logs..."
ssh "$USERNAME@$DEVICE_IP" "cat $TRACE_DIR/trace" > "./trace_${MODULE_NAME}.txt"
echo "Trace log saved as ./trace_${MODULE_NAME}.txt"

