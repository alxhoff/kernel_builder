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
Usage: $0 <duration_in_seconds> <tracepoint>

Description:
  Automates a tracing workflow on the target device by enabling a tracepoint, recording function calls for a specified duration, and processing logs into a human-readable report.

Arguments:
  <duration_in_seconds>  Duration of the tracing session.
  <tracepoint>           The tracepoint to enable and monitor during the session.

Examples:
  Trace for 10 seconds using the sched:sched_switch tracepoint:
    $0 10 sched:sched_switch --device-ip 192.168.1.100

  Trace for 20 seconds using a custom tracepoint:
    $0 20 alex_trigger --device-ip 192.168.1.100
EOF
  exit 0
fi

DURATION="$1"
TRACEPOINT="$2"
TRACE_FILE="/tmp/trace_${TRACEPOINT}.dat"
REPORT_FILE="/tmp/report_${TRACEPOINT}.txt"

TRACEPOINT_PATH="/sys/kernel/debug/tracing/events/$TRACEPOINT/$TRACEPOINT"

# Verify tracepoint existence
if ! ssh root@"$DEVICE_IP" "[ -d $TRACEPOINT_PATH ]"; then
  echo "Error: Tracepoint '$TRACEPOINT' does not exist on target $DEVICE_IP. Use list_tracepoints.sh to verify."
  exit 1
fi

# Clear previous logs
echo "Clearing previous logs on target $DEVICE_IP..."
ssh root@"$DEVICE_IP" "trace-cmd reset"

# Enable the tracepoint
echo "Enabling tracepoint: $TRACEPOINT on target $DEVICE_IP..."
ssh root@"$DEVICE_IP" "echo 1 > $TRACEPOINT_PATH/enable"

# Add a trigger to start tracing when the tracepoint is hit
echo "Adding 'traceon' trigger to $TRACEPOINT on target $DEVICE_IP..."
ssh root@"$DEVICE_IP" "echo traceon > $TRACEPOINT_PATH/trigger" || {
  echo "Warning: Could not add traceon trigger to $TRACEPOINT. Continuing without trigger."
}

# Start tracing using trace-cmd
echo "Recording trace data for $DURATION seconds on target $DEVICE_IP..."
ssh root@"$DEVICE_IP" "trace-cmd record -p function_graph -o $TRACE_FILE sleep $DURATION"

# Generate human-readable report
echo "Generating human-readable report on target $DEVICE_IP..."
ssh root@"$DEVICE_IP" "trace-cmd report -i $TRACE_FILE > $REPORT_FILE"

# Retrieve the report to the host
echo "Fetching human-readable report from target $DEVICE_IP..."
scp root@"$DEVICE_IP":"$REPORT_FILE" . || {
  echo "Error: Failed to fetch the report file from target $DEVICE_IP."
  exit 1
}

# Disable the tracepoint and cleanup
echo "Disabling tracepoint $TRACEPOINT on target $DEVICE_IP..."
ssh root@"$DEVICE_IP" "echo 0 > $TRACEPOINT_PATH/enable"
ssh root@"$DEVICE_IP" "echo '' > $TRACEPOINT_PATH/trigger"
ssh root@"$DEVICE_IP" "trace-cmd reset"

echo "Tracing workflow completed. Report saved as report_${TRACEPOINT}.txt."

