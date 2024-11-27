#!/bin/bash

# Script to control tracing (start/stop/duration-based)

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
Usage: $0 --start | --stop | --start-duration <seconds>

Description:
  Controls tracing on the target device.

Examples:
  ./control_tracing.sh --start
  ./control_tracing.sh --stop
  ./control_tracing.sh --start-duration 15
EOF
  exit 0
fi

ACTION="$1"
DURATION="${2:-15}"  # Default duration is 15 seconds

if [ "$ACTION" == "--start" ]; then
  ssh root@"$DEVICE_IP" "echo 1 > /sys/kernel/debug/tracing/tracing_on"
  echo "Tracing started on $DEVICE_IP"
elif [ "$ACTION" == "--stop" ]; then
  ssh root@"$DEVICE_IP" "echo 0 > /sys/kernel/debug/tracing/tracing_on"
  echo "Tracing stopped on $DEVICE_IP"
elif [ "$ACTION" == "--start-duration" ]; then
  ssh root@"$DEVICE_IP" "echo 1 > /sys/kernel/debug/tracing/tracing_on; sleep $DURATION; echo 0 > /sys/kernel/debug/tracing/tracing_on"
  echo "Tracing started for $DURATION seconds on $DEVICE_IP"
else
  echo "Invalid option. Use --help for usage details."
  exit 1
fi

