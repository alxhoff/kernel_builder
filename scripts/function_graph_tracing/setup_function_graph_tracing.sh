#!/bin/bash

# Usage: ./setup_function_graph_tracing.sh [<device-ip>] [--start-trace] [--stop-trace] [--add-filter <function>] [--remove-filter <function>] [--list-filters] [--clear-filters] [--trace-single-function <module> <function>] [--trace-all-functions <module>] [--trace-gpio] [--enable-boot-trace] [--disable-boot-trace] [--duration <seconds>] [--dry-run] [--help]
# Options:
#   <device-ip>                The IP address of the remote device (required unless device_ip file is present).
#   --start-trace              Starts function graph tracing.
#   --stop-trace               Stops function graph tracing.
#   --add-filter <func>        Adds a function to the ftrace filter.
#   --remove-filter <func>     Removes a function from the ftrace filter.
#   --list-filters             Lists all currently active filters.
#   --clear-filters            Clears all filters.
#   --trace-single-function    Traces a single function from a specified module.
#   --trace-all-functions      Traces all functions from a specified module.
#   --trace-gpio               Interactive workflow for tracing GPIO operations.
#   --enable-boot-trace        Enables function graph tracing during boot.
#   --disable-boot-trace       Disables function graph tracing during boot.
#   --duration <seconds>       Traces for a specified duration, then stops automatically.
#   --dry-run                  Simulate the operations without making actual changes.
#   --help                     Shows this help message.

show_help() {
  cat << EOF
This script sets up and manages function graph tracing on a Linux system with ftrace enabled.

Options:
  <device-ip>                The IP address of the remote device (required unless device_ip file is present).
  --start-trace              Starts function graph tracing.
  --stop-trace               Stops function graph tracing.
  --add-filter <func>        Adds a function to the ftrace filter.
  --remove-filter <func>     Removes a function from the ftrace filter.
  --list-filters             Lists all currently active filters.
  --clear-filters            Clears all filters.
  --trace-single-function    Traces a single function from a specified module.
  --trace-all-functions      Traces all functions from a specified module.
  --trace-gpio               Interactive workflow for tracing GPIO operations.
  --enable-boot-trace        Enables function graph tracing during boot.
  --disable-boot-trace       Disables function graph tracing during boot.
  --duration <seconds>       Traces for a specified duration, then stops automatically.
  --dry-run                  Simulate the operations without making actual changes.
  --help                     Shows this help message.

Example Workflows:
-----------------

1. **Start and Stop Tracing Manually**:
   Start tracing and leave it running:
   ./setup_function_graph_tracing.sh <device-ip> --start-trace
   Perform your kernel interactions, then stop tracing:
   ./setup_function_graph_tracing.sh <device-ip> --stop-trace

2. **Trace for a Specific Duration**:
   Start tracing and stop automatically after 10 seconds:
   ./setup_function_graph_tracing.sh <device-ip> --start-trace --duration 10

3. **Filter Specific Functions**:
   Add a filter for specific functions:
   ./setup_function_graph_tracing.sh <device-ip> --add-filter my_function
   List active filters:
   ./setup_function_graph_tracing.sh <device-ip> --list-filters
   Remove a filter:
   ./setup_function_graph_tracing.sh <device-ip> --remove-filter my_function
   Clear all filters:
   ./setup_function_graph_tracing.sh <device-ip> --clear-filters

4. **Trace a Single Function in a Module**:
   Trace a specific function `my_function` from the module `my_module`:
   ./setup_function_graph_tracing.sh <device-ip> --trace-single-function my_module my_function

5. **Trace All Functions in a Module**:
   Trace all functions from the module `my_module`:
   ./setup_function_graph_tracing.sh <device-ip> --trace-all-functions my_module

6. **Interactive GPIO Tracing**:
   Perform GPIO-related tracing interactively:
   ./setup_function_graph_tracing.sh <device-ip> --trace-gpio
   This will:
     - Trace GPIO interactions.
     - Export a GPIO pin, set its direction, and toggle its value.
     - Save the trace log to ./trace_log_gpio.txt.

7. **Enable Boot-Time Tracing**:
   Enable function graph tracing during boot:
   ./setup_function_graph_tracing.sh <device-ip> --enable-boot-trace
   Reboot the device for the changes to take effect.

8. **Disable Boot-Time Tracing**:
   Disable function graph tracing during boot:
   ./setup_function_graph_tracing.sh <device-ip> --disable-boot-trace
   Reboot the device to stop tracing during boot.

9. **Simulate Operations with Dry-Run**:
   Test the script without making actual changes:
   ./setup_function_graph_tracing.sh <device-ip> --start-trace --dry-run
EOF
}

# Get the device IP
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <device-ip> [options]"
    exit 1
  fi
  DEVICE_IP=$1
  shift
fi

TRACE_DIR="/sys/kernel/debug/tracing"
BOOT_CONFIG_FILE="/boot/extlinux/extlinux.conf"
USERNAME="root"

# Parse Arguments
ACTION=""
FILTER_FUNCTION=""
MODULE_NAME=""
GPIO_PIN="507"  # Default GPIO pin for GPIO tracing workflow
DURATION=0
DRY_RUN=false

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --start-trace) ACTION="start-trace" ;;
    --stop-trace) ACTION="stop-trace" ;;
    --add-filter) ACTION="add-filter"; FILTER_FUNCTION="$2"; shift ;;
    --remove-filter) ACTION="remove-filter"; FILTER_FUNCTION="$2"; shift ;;
    --list-filters) ACTION="list-filters" ;;
    --clear-filters) ACTION="clear-filters" ;;
    --trace-single-function) ACTION="trace-single-function"; MODULE_NAME="$2"; FILTER_FUNCTION="$3"; shift 2 ;;
    --trace-all-functions) ACTION="trace-all-functions"; MODULE_NAME="$2"; shift ;;
    --trace-gpio) ACTION="trace-gpio" ;;
    --enable-boot-trace) ACTION="enable-boot-trace" ;;
    --disable-boot-trace) ACTION="disable-boot-trace" ;;
    --duration) DURATION=$2; shift ;;
    --dry-run) DRY_RUN=true ;;
    --help) show_help; exit 0 ;;
    *) echo "Unknown argument: $1"; show_help; exit 1 ;;
  esac
  shift
done

# Functions for tracing actions
start_trace() {
  echo "Starting function graph tracing..."
  ssh "$USERNAME@$DEVICE_IP" "echo 'function_graph' > $TRACE_DIR/current_tracer && echo 1 > $TRACE_DIR/tracing_on"
  if [ "$DURATION" -gt 0 ]; then
    echo "Tracing for $DURATION seconds..."
    sleep "$DURATION"
    stop_trace
  fi
}

stop_trace() {
  echo "Stopping tracing and fetching logs..."
  ssh "$USERNAME@$DEVICE_IP" "echo 0 > $TRACE_DIR/tracing_on"
  ssh "$USERNAME@$DEVICE_IP" "cat $TRACE_DIR/trace" > ./trace_log.txt
  echo "Trace log saved as ./trace_log.txt"
}

enable_boot_trace() {
  echo "Enabling function graph tracing during boot..."
  ssh "$USERNAME@$DEVICE_IP" "sed -i '/^APPEND /s/$/ ftrace=function_graph/' $BOOT_CONFIG_FILE"
  echo "Boot-time tracing enabled. Reboot the device for changes to take effect."
}

disable_boot_trace() {
  echo "Disabling function graph tracing during boot..."
  ssh "$USERNAME@$DEVICE_IP" "sed -i '/ftrace=function_graph/d' $BOOT_CONFIG_FILE"
  echo "Boot-time tracing disabled. Reboot the device for changes to take effect."
}

add_filter() {
  echo "Adding function '$FILTER_FUNCTION' to trace filter..."
  ssh "$USERNAME@$DEVICE_IP" "echo '$FILTER_FUNCTION' > $TRACE_DIR/set_ftrace_filter"
}

remove_filter() {
  echo "Removing function '$FILTER_FUNCTION' from trace filter..."
  ssh "$USERNAME@$DEVICE_IP" "sed -i '/^$FILTER_FUNCTION\$/d' $TRACE_DIR/set_ftrace_filter"
}

list_filters() {
  echo "Listing active trace filters..."
  ssh "$USERNAME@$DEVICE_IP" "cat $TRACE_DIR/set_ftrace_filter"
}

clear_filters() {
  echo "Clearing all trace filters..."
  ssh "$USERNAME@$DEVICE_IP" "echo > $TRACE_DIR/set_ftrace_filter"
}

trace_single_function() {
  echo "Tracing single function '$FILTER_FUNCTION' from module '$MODULE_NAME'..."
  ssh "$USERNAME@$DEVICE_IP" "echo '$FILTER_FUNCTION' > $TRACE_DIR/set_ftrace_filter"
  start_trace
}

trace_all_functions() {
  echo "Tracing all functions in module '$MODULE_NAME'..."
  ssh "$USERNAME@$DEVICE_IP" "echo '${MODULE_NAME}:*' > $TRACE_DIR/set_ftrace_filter"
  start_trace
}

trace_gpio() {
  echo "Interactive GPIO tracing workflow..."
  ssh "$USERNAME@$DEVICE_IP" <<EOF
    echo 'gpio_request' > $TRACE_DIR/set_ftrace_filter
    echo 'gpio_direction_output' >> $TRACE_DIR/set_ftrace_filter
    echo 'gpio_set_value' >> $TRACE_DIR/set_ftrace_filter
    echo 'function_graph' > $TRACE_DIR/current_tracer
    echo 1 > $TRACE_DIR/tracing_on
    echo $GPIO_PIN > /sys/class/gpio/export
    echo out > /sys/class/gpio/gpio$GPIO_PIN/direction
    echo 1 > /sys/class/gpio/gpio$GPIO_PIN/value
    echo 0 > /sys/class/gpio/gpio$GPIO_PIN/value
    echo 0 > $TRACE_DIR/tracing_on
EOF
  ssh "$USERNAME@$DEVICE_IP" "cat $TRACE_DIR/trace" > ./trace_log_gpio.txt
  echo "Trace log saved as ./trace_log_gpio.txt"
}

# Execute the selected action
case $ACTION in
  start-trace) start_trace ;;
  stop-trace) stop_trace ;;
  add-filter) add_filter ;;
  remove-filter) remove_filter ;;
  list-filters) list_filters ;;
  clear-filters) clear_filters ;;
  trace-single-function) trace_single_function ;;
  trace-all-functions) trace_all_functions ;;
  trace-gpio) trace_gpio ;;
  enable-boot-trace) enable_boot_trace ;;
  disable-boot-trace) disable_boot_trace ;;
  *) echo "Invalid or no action specified."; show_help; exit 1 ;;
esac

