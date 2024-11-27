#!/bin/bash

# Script to retrieve and process logs

SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
DEVICE_IP_FILE="$SCRIPT_DIR/device_ip"

if [ -f "$DEVICE_IP_FILE" ]; then
  DEVICE_IP=$(cat "$DEVICE_IP_FILE")
else
  echo "Error: Device IP file not found."
  exit 1
fi

if [[ "$1" == "--help" ]]; then
  cat << EOF
Usage: $0 [--output <file>]

Description:
  Retrieves logs from the target device and saves them locally.

Options:
  --output <file>  Specify the output file for the logs (default: trace_report.txt).

Examples:
  ./retrieve_logs.sh
  ./retrieve_logs.sh --output my_trace_logs.txt
EOF
  exit 0
fi

OUTPUT_FILE="trace_report.txt"
if [[ "$1" == "--output" && -n "$2" ]]; then
  OUTPUT_FILE="$2"
fi

ssh root@"$DEVICE_IP" "cat /sys/kernel/debug/tracing/trace" > "$OUTPUT_FILE"
echo "Logs retrieved and saved to $OUTPUT_FILE"

