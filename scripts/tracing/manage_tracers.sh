#!/bin/bash

# Script to manage tracers

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
Usage: $0 --list | --enable <tracer>

Description:
  Lists or enables tracers on the target device.

Examples:
  ./manage_tracers.sh --list
  ./manage_tracers.sh --enable function_graph
EOF
  exit 0
fi

if [ "$1" == "--list" ]; then
  ssh root@"$DEVICE_IP" "cat /sys/kernel/debug/tracing/available_tracers"
elif [ "$1" == "--enable" ] && [ -n "$2" ]; then
  ssh root@"$DEVICE_IP" "echo $2 > /sys/kernel/debug/tracing/current_tracer"
  echo "Tracer '$2' enabled on $DEVICE_IP"
else
  echo "Invalid option. Use --help for usage details."
  exit 1
fi

