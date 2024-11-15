#!/bin/bash

# Trace a single function from a specified module
# Usage: ./trace_single_function.sh [<device-ip>] <module-name> <function-name> [--duration <seconds>]

if [[ "$1" == "--help" ]]; then
  cat << EOF
Usage: ./trace_single_function.sh [<device-ip>] <module-name> <function-name> [--duration <seconds>]

Description:
  This script traces a specific function within a kernel module using ftrace's function graph tracer.

Parameters:
  <device-ip>       IP address of the target device (e.g., Jetson Orin). Optional if 'device_ip' file exists.
  <module-name>     Name of the kernel module containing the function to trace.
  <function-name>   Name of the function to trace.
  --duration        (Optional) Specify the tracing duration in seconds.

Workflow:
  1. Reads the device IP from a 'device_ip' file in the script's parent directory, or uses the provided argument.
  2. Adds the specified function to the ftrace filter.
  3. Starts the function graph tracer.
  4. Stops the tracing either after a duration or upon user confirmation.
  5. Saves the trace log as ./trace_log_single_function.txt.

Examples:
  Trace function 'my_function' in module 'my_module' for 10 seconds:
    ./trace_single_function.sh 192.168.1.100 my_module my_function --duration 10

  Trace function 'probe' in module 'usb_driver' until user stops:
    ./trace_single_function.sh usb_driver probe

  Trace function when 'device_ip' file exists:
    ./trace_single_function.sh my_module my_function --duration 5
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
    echo "Usage: $0 [<device-ip>] <module-name> <function-name> [--duration <seconds>]"
    exit 1
  fi
  DEVICE_IP=$1
  shift
fi

MODULE_NAME="$1"
FUNCTION_NAME="$2"
DURATION=0

# Optional duration
if [[ "$3" == "--duration" && -n "$4" ]]; then
  DURATION=$4
fi

TRACE_DIR="/sys/kernel/debug/tracing"
USERNAME="root"

if [ -z "$MODULE_NAME" ] || [ -z "$FUNCTION_NAME" ]; then
  echo "Usage: $0 [<device-ip>] <module-name> <function-name> [--duration <seconds>]"
  exit 1
fi

echo "Adding function '$FUNCTION_NAME' from module '$MODULE_NAME' to trace filter..."
ssh "$USERNAME@$DEVICE_IP" "echo '$FUNCTION_NAME' > $TRACE_DIR/set_ftrace_filter"

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
ssh "$USERNAME@$DEVICE_IP" "cat $TRACE_DIR/trace" > ./trace_log_single_function.txt
echo "Trace log saved as ./trace_log_single_function.txt

