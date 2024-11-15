#!/bin/bash

# Interactive GPIO tracing workflow
# Usage: ./trace_gpio.sh [<device-ip>] [<gpio-pin>]

if [[ "$1" == "--help" ]]; then
  cat << EOF
Usage: ./trace_gpio.sh [<device-ip>] [<gpio-pin>]

Description:
  This script traces GPIO operations interactively using ftrace's function graph tracer. It automates GPIO interactions
  and logs the kernel function calls.

Parameters:
  <device-ip>       IP address of the target device (e.g., Jetson Orin). Optional if 'device_ip' file exists.
  <gpio-pin>        (Optional) GPIO pin number to trace. Defaults to 507.

Workflow:
  1. Reads the device IP from a 'device_ip' file in the script's parent directory, or uses the provided argument.
  2. Adds GPIO driver functions (gpio_request, gpio_direction_output, gpio_set_value) to the ftrace filter.
  3. Starts the function graph tracer.
  4. Performs the following GPIO operations:
     - Exports the specified GPIO pin.
     - Sets the GPIO pin direction to output.
     - Toggles the GPIO value between HIGH and LOW.
  5. Stops tracing and saves the trace log as ./trace_log_gpio.txt.

Examples:
  Trace GPIO operations on GPIO pin 507 (default):
    ./trace_gpio.sh

  Trace GPIO operations on GPIO pin 200 with device IP provided:
    ./trace_gpio.sh 192.168.1.100 200
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
    echo "Usage: $0 [<device-ip>] [<gpio-pin>]"
    exit 1
  fi
  DEVICE_IP=$1
  shift
fi

GPIO_PIN="${1:-507}"  # Default GPIO pin is 507 if not specified
TRACE_DIR="/sys/kernel/debug/tracing"
USERNAME="root"

echo "Adding GPIO driver functions to trace filter..."
ssh "$USERNAME@$DEVICE_IP" "echo 'gpio_request' > $TRACE_DIR/set_ftrace_filter"
ssh "$USERNAME@$DEVICE_IP" "echo 'gpio_direction_output' >> $TRACE_DIR/set_ftrace_filter"
ssh "$USERNAME@$DEVICE_IP" "echo 'gpio_set_value' >> $TRACE_DIR/set_ftrace_filter"

echo "Starting function graph tracing..."
ssh "$USERNAME@$DEVICE_IP" "echo 'function_graph' > $TRACE_DIR/current_tracer && echo 1 > $TRACE_DIR/tracing_on"

echo "Exporting GPIO pin $GPIO_PIN..."
ssh "$USERNAME@$DEVICE_IP" "echo $GPIO_PIN > /sys/class/gpio/export"

echo "Setting GPIO direction to 'out'..."
ssh "$USERNAME@$DEVICE_IP" "echo 'out' > /sys/class/gpio/gpio$GPIO_PIN/direction"

echo "Setting GPIO value to HIGH (1)..."
ssh "$USERNAME@$DEVICE_IP" "echo 1 > /sys/class/gpio/gpio$GPIO_PIN/value"

echo "Setting GPIO value to LOW (0)..."
ssh "$USERNAME@$DEVICE_IP" "echo 0 > /sys/class/gpio/gpio$GPIO_PIN/value"

echo "Stopping tracing..."
ssh "$USERNAME@$DEVICE_IP" "echo 0 > $TRACE_DIR/tracing_on"

echo "Fetching trace logs..."
ssh "$USERNAME@$DEVICE_IP" "cat $TRACE_DIR/trace" > ./trace_log_gpio.txt
echo "Trace log saved as ./trace_log_gpio.txt"

