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

# Generate a report from recorded trace data
if [[ "$1" == "--help" || -z "$1" ]]; then
  cat << EOF
Usage: $0 <trace_file>

Description:
  Processes a recorded trace file on the target device and generates a human-readable report.

Arguments:
  <trace_file>  Path to the recorded trace file on the target device.

Examples:
  Generate a report from a trace file:
    $0 trace_record.dat --device-ip 192.168.1.100
EOF
  exit 0
fi

TRACE_FILE="$1"

echo "Generating trace report for $TRACE_FILE on target $DEVICE_IP..."
ssh root@"$DEVICE_IP" "trace-cmd report -i $TRACE_FILE" > "report_$TRACE_FILE.txt"
echo "Report saved as report_$TRACE_FILE.txt."

