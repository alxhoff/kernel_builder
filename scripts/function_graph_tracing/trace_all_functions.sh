#!/bin/bash

# Trace all functions from a specified module
# Usage: ./trace_all_functions.sh [<device-ip>] <module-name> [--duration <seconds>]

if [[ "$1" == "--help" ]]; then
  cat << EOF
Usage: ./trace_all_functions.sh [<device-ip>] <module-name> [--duration <seconds>]

Description:
  This script traces all functions within a specified kernel module using ftrace's function graph tracer.

Parameters:
  <device-ip>       IP address of the target device (e.g., Jetson Orin). Optional if 'device_ip' file exists.
  <module-name>     Name of the kernel module to trace.
  --duration        (Optional) Specify the tracing duration in seconds.

Workflow:
  1. Reads the device IP from a 'device_ip' file in the script's parent directory, or uses the provided argument.
  2. Adds all functions from the specified module to the ftrace filter.
  3. Starts the function graph tracer.
  4. Stops the tracing either after a duration or upon user confirmation.
  5. Saves the trace log as ./trace_log_all_functions.txt.

Examples:
  Trace all functions in the 'my_module' kernel module for 15 seconds:
    ./trace_all_functions.sh 192.168.1.100 my_module --duration 15

  Trace all functions in the 'usb_driver' kernel module until user stops:
    ./trace_all_functions.sh usb_driver

  Trace all functions when 'device_ip' file exists:
    ./trace_all_functions.sh my_module --duration 10
EOF
  exit 0
fi

# Get the device IP
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ -z "$1" ] || [[ "$1" == "--"* ]]; then
    echo "Error: <device-ip> is required if 'device_ip' file does not exist."
    echo "Usage: $0 [<device-ip>] <module-name> [--duration <seconds>]"
    exit 1
  fi
  DEVICE_IP=$1
  shift
fi

MODULE_NAME="$1"
DURATION=0

# Optional duration
if [[ "$2" == "--duration" && -n "$3" ]]; then
  DURATION=$3
fi

TRACE_DIR="/sys/kernel/debug/tracing"
USERNAME="root"

if [ -z "$MODULE_NAME" ]; then
  echo "Usage: $0 [<device-ip>] <module-name> [--duration <seconds>]"
  exit 1
fi

echo "Adding all functions from module '$MODULE_NAME' to trace filter..."
ssh "$USERNAME@$DEVICE_IP" "echo '${MODULE_NAME}:*' > $TRACE_DIR/set_ftrace_filter"

echo "Starting function graph tracing..."
ssh "$USERNAME@$DEVICE_IP" "echo 'function_graph' > $TRACE_DIR/current_tracer && echo 1 > $TRACE_DIR/tracing_on"

if [ "$DURATION" -gt 0 ]; then
  echo "Tracing for $DURATION seconds..."
  sleep "$DURATION"
  echo "Stopping tracing..."
  ssh "$USERNAME@$DEVICE_IP" "echo 0 > $TRACE_DIR/tracing_on"
else
  read -p "Trigger the module functionality now, then press Enter to stop tracing..."
  ssh "$USERNAME@$DEVICE_IP" "echo 0 > $TRACE_DIR/tracing_on"
fi

echo "Fetching trace logs..."
ssh "$USERNAME@$DEVICE_IP" "cat $TRACE_DIR/trace" > ./trace_log_all_functions.txt
echo "Trace log saved as ./trace_log_all_functions.txt"

