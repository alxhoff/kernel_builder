#!/bin/bash

# Script to clear logs and prepare tracing environment

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
Usage: $0

Description:
  Clears logs, filters, and resets the tracing environment on the target device.

Examples:
  ./prepare_tracing.sh
EOF
  exit 0
fi

ssh root@"$DEVICE_IP" <<EOF
echo > /sys/kernel/debug/tracing/trace
echo > /sys/kernel/debug/tracing/set_ftrace_filter
echo nop > /sys/kernel/debug/tracing/current_tracer
EOF

echo "Tracing environment cleared on target device: $DEVICE_IP"

