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

# List all available kernel tracepoints
if [[ "$1" == "--help" ]]; then
  cat << EOF
Usage: $0

Description:
  Lists all available kernel tracepoints on the target device that can be enabled for tracing.

Examples:
  List all available tracepoints:
    $0 --device-ip 192.168.1.100
EOF
  exit 0
fi

echo "Listing available tracepoints on target $DEVICE_IP..."
ssh root@"$DEVICE_IP" "cat /sys/kernel/debug/tracing/available_events"

