#!/bin/bash

SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

# Retrieve or parse device IP
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
  echo "Using device IP from file: $DEVICE_IP"
else
  if [[ "$1" == "--device-ip" && -n "$2" ]]; then
    DEVICE_IP=$2
    shift 2
    echo "Using provided device IP: $DEVICE_IP"
  else
    echo "Error: --device-ip <ip-address> is required if 'device_ip' file does not exist."
    exit 1
  fi
fi

if [[ "$1" == "--help" || "$#" -lt 2 ]]; then
  cat << EOF
Usage: $0 <duration_in_seconds> <tracepoint> [<functions_to_trace>...]

Description:
  Traces only the function call stack associated with a specific tracepoint.

Arguments:
  <duration_in_seconds>  Duration of the tracing session.
  <tracepoint>           The tracepoint to enable and monitor during the session.
  <functions_to_trace>   (Optional) Space-separated list of functions to add to set_ftrace_filter.

Examples:
  Trace for 10 seconds using the alex_trigger tracepoint:
    $0 10 alex_trigger --device-ip 192.168.1.100

  Trace specific functions for 10 seconds:
    $0 10 alex_trigger func1 func2 --device-ip 192.168.1.100
EOF
  exit 0
fi

DURATION="$1"
TRACEPOINT="$2"
TRACE_FILE="/tmp/trace_${TRACEPOINT}.dat"
REPORT_FILE="./trace_${TRACEPOINT}_callstack.txt"
TRACEPOINT_PATH="/sys/kernel/debug/tracing/events/$TRACEPOINT/$TRACEPOINT"

# Additional functions to trace
shift 2
FUNCTIONS_TO_TRACE=("$@")

# Verify tracepoint existence
echo "Checking existence of tracepoint '$TRACEPOINT' on target $DEVICE_IP..."
ssh root@"$DEVICE_IP" "[ -d $TRACEPOINT_PATH ]" || {
  echo "Error: Tracepoint '$TRACEPOINT' does not exist on target $DEVICE_IP. Use list_tracepoints.sh to verify."
  exit 1
}

# Clear previous logs and filters
echo "Clearing previous logs and filters on target $DEVICE_IP..."
ssh root@"$DEVICE_IP" "echo > /sys/kernel/debug/tracing/trace"
ssh root@"$DEVICE_IP" "echo > /sys/kernel/debug/tracing/set_ftrace_filter"

# Enable function graph tracer
echo "Enabling function graph tracer on target $DEVICE_IP..."
ssh root@"$DEVICE_IP" "echo function_graph > /sys/kernel/debug/tracing/current_tracer"

# Enable the tracepoint only if not already enabled
echo "Checking if tracepoint $TRACEPOINT is already enabled..."
if ssh root@"$DEVICE_IP" "grep -q '^1' $TRACEPOINT_PATH/enable"; then
  echo "Tracepoint $TRACEPOINT is already enabled on target $DEVICE_IP."
else
  echo "Enabling tracepoint: $TRACEPOINT on target $DEVICE_IP..."
  ssh root@"$DEVICE_IP" "echo 1 > $TRACEPOINT_PATH/enable" || {
    echo "Error: Failed to enable tracepoint $TRACEPOINT on target $DEVICE_IP."
    exit 1
  }
fi

# Add a trigger to start function tracing only when the tracepoint is hit
echo "Setting 'traceon' trigger for $TRACEPOINT on target $DEVICE_IP..."
ssh root@"$DEVICE_IP" "[ -e $TRACEPOINT_PATH/trigger ] && echo traceon > $TRACEPOINT_PATH/trigger" || {
  echo "Warning: Could not add 'traceon' trigger to $TRACEPOINT. Continuing without trigger."
}

# Start tracing with trace-cmd
echo "Recording trace data for $DURATION seconds on target $DEVICE_IP..."
ssh root@"$DEVICE_IP" "trace-cmd record -p function_graph -e $TRACEPOINT -o $TRACE_FILE sleep $DURATION"

# Generate human-readable report
echo "Generating human-readable report using trace-cmd report..."
ssh root@"$DEVICE_IP" "trace-cmd report -i $TRACE_FILE" > "$REPORT_FILE" || {
  echo "Error: Failed to generate report from trace file."
  exit 1
}

# Disable the tracepoint and cleanup
echo "Disabling tracepoint $TRACEPOINT on target $DEVICE_IP..."
ssh root@"$DEVICE_IP" "echo 0 > $TRACEPOINT_PATH/enable"

echo "Removing 'traceon' trigger for $TRACEPOINT on target $DEVICE_IP..."
ssh root@"$DEVICE_IP" "[ -e $TRACEPOINT_PATH/trigger ] && echo '' > $TRACEPOINT_PATH/trigger"

echo "Disabling function graph tracer on target $DEVICE_IP..."
ssh root@"$DEVICE_IP" "echo nop > /sys/kernel/debug/tracing/current_tracer"

echo "Clearing trace log on target $DEVICE_IP..."
ssh root@"$DEVICE_IP" "echo > /sys/kernel/debug/tracing/trace"

echo "Tracing completed. Human-readable report saved to $REPORT_FILE."

