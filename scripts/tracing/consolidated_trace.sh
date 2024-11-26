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

# Consolidated script for recording traces or starting real-time tracing
if [[ "$1" == "--help" || "$#" -lt 1 ]]; then
  cat << EOF
Usage: $0 [--record <duration_in_seconds> | --start <duration_in_seconds>]

Description:
  Manages kernel event tracing by recording trace data or starting real-time tracing sessions.

Options:
  --record <duration>   Record kernel events for the specified duration and save to a trace file.
  --start <duration>    Start real-time tracing for the specified duration without saving the data.

Examples:
  Record trace data for 15 seconds:
    $0 --device-ip 192.168.1.100 --record 15

  Start real-time tracing for 10 seconds:
    $0 --device-ip 192.168.1.100 --start 10
EOF
  exit 0
fi

TRACE_DIR="/sys/kernel/debug/tracing"
LOG_FILE="trace_record.dat"

case $1 in
  --record)
    if [[ -z "$2" ]]; then
      echo "Error: Duration must be specified for --record."
      exit 1
    fi
    echo "Recording trace data for $2 seconds on target $DEVICE_IP..."
    ssh root@"$DEVICE_IP" "trace-cmd record -p function_graph -o $LOG_FILE sleep $2"
    echo "Trace recorded to $LOG_FILE on target $DEVICE_IP"
    ;;
  --start)
    if [[ -z "$2" ]]; then
      echo "Error: Duration must be specified for --start."
      exit 1
    fi
    echo "Starting real-time tracing for $2 seconds on target $DEVICE_IP..."
    ssh root@"$DEVICE_IP" "trace-cmd start -p function_graph; sleep $2; trace-cmd stop"
    echo "Real-time tracing completed on target $DEVICE_IP. No data saved."
    ;;
  *)
    echo "Invalid option. Use --help for usage instructions."
    exit 1
    ;;
esac

