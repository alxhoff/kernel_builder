#!/bin/bash

# Script to set filters for functions or modules

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
Usage: $0 --modules <module1 module2> | --functions <func1 func2>

Description:
  Sets filters for modules or functions to narrow tracing focus.

Examples:
  ./set_filter.sh --modules module1 module2
  ./set_filter.sh --functions func1 func2
EOF
  exit 0
fi

FILTER_TYPE="$1"
shift
FILTER_VALUES=("$@")

if [ "$FILTER_TYPE" == "--modules" ]; then
  echo "Setting module filters on $DEVICE_IP: ${FILTER_VALUES[*]}"
  for module in "${FILTER_VALUES[@]}"; do
    ssh root@"$DEVICE_IP" "cat /sys/kernel/debug/tracing/available_filter_functions | grep $module >> /sys/kernel/debug/tracing/set_ftrace_filter"
  done
elif [ "$FILTER_TYPE" == "--functions" ]; then
  echo "Setting function filters on $DEVICE_IP: ${FILTER_VALUES[*]}"
  for func in "${FILTER_VALUES[@]}"; do
    ssh root@"$DEVICE_IP" "echo $func >> /sys/kernel/debug/tracing/set_ftrace_filter"
  done
else
  echo "Invalid option. Use --help for usage details."
  exit 1
fi

