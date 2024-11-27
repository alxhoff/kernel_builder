#!/bin/bash

# Script to manage tracepoints

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
Usage: $0 --list | --enable <tracepoint> | --disable <tracepoint>

Description:
  Lists, enables, or disables tracepoints on the target device.

Examples:
  ./tracepoints.sh --list
  ./tracepoints.sh --enable sched:sched_switch
  ./tracepoints.sh --disable sched:sched_switch
EOF
  exit 0
fi

ACTION="$1"
TRACEPOINT="$2"

if [ "$ACTION" == "--enable" ] && [ -n "$TRACEPOINT" ]; then
  ssh root@"$DEVICE_IP" "echo 1 > /sys/kernel/debug/tracing/events/$TRACEPOINT/enable"
  echo "Tracepoint '$TRACEPOINT' enabled on $DEVICE_IP"
elif [ "$ACTION" == "--disable" ] && [ -n "$TRACEPOINT" ]; then
  ssh root@"$DEVICE_IP" "echo 0 > /sys/kernel/debug/tracing/events/$TRACEPOINT/enable"
  echo "Tracepoint '$TRACEPOINT' disabled on $DEVICE_IP"
elif [ "$ACTION" == "--list" ]; then
  ssh root@"$DEVICE_IP" "cat /sys/kernel/debug/tracing/available_events"
else
  echo "Invalid option. Use --help for usage details."
  exit 1
fi

