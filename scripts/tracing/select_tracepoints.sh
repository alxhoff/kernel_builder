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

TRACE_DIR="/sys/kernel/debug/tracing"

function show_help() {
    echo "Usage: $0 [--list | --enable <tracepoint> | --disable <tracepoint>] [--device-ip <ip-address>]"
    echo
    echo "Options:"
    echo "  --list                 List all available tracepoints on the target."
    echo "  --enable <tracepoint>  Enable tracing for the specified tracepoint."
    echo "  --disable <tracepoint> Disable tracing for the specified tracepoint."
    echo
    echo "Examples:"
    echo "  $0 --list --device-ip 192.168.1.100"
    echo "  $0 --enable sched:sched_switch --device-ip 192.168.1.100"
    echo "  $0 --disable sched:sched_switch --device-ip 192.168.1.100"
}

# Check for valid arguments
if [[ "$#" -lt 1 ]]; then
  show_help
  exit 1
fi

case $1 in
  --list)
    echo "Listing available tracepoints on target $DEVICE_IP..."
    ssh root@"$DEVICE_IP" "cat $TRACE_DIR/available_events" || {
      echo "Error: Failed to list tracepoints on target $DEVICE_IP."
      exit 1
    }
    ;;
  --enable)
    if [[ -z "$2" ]]; then
      echo "Error: Tracepoint name is required."
      exit 1
    fi

    TRACEPOINT="$2"
    TRACEPOINT_PATH="$TRACE_DIR/events/$TRACEPOINT"

    echo "Enabling tracepoint: $TRACEPOINT on target $DEVICE_IP..."
    ssh root@"$DEVICE_IP" "if [ -d $TRACEPOINT_PATH ]; then
      echo 1 > $TRACEPOINT_PATH/enable;
      echo function_graph > $TRACE_DIR/current_tracer;
      echo traceon > $TRACEPOINT_PATH/$TRACEPOINT/trigger;
    else
      echo 'Error: Tracepoint $TRACEPOINT does not exist.';
      exit 1;
    fi" || {
      echo "Error: Failed to enable tracepoint $TRACEPOINT on target $DEVICE_IP."
      exit 1
    }
    ;;
  --disable)
    if [[ -z "$2" ]]; then
      echo "Error: Tracepoint name is required."
      exit 1
    fi

    TRACEPOINT="$2"
    TRACEPOINT_PATH="$TRACE_DIR/events/$TRACEPOINT"

    echo "Disabling tracepoint: $TRACEPOINT on target $DEVICE_IP..."
    ssh root@"$DEVICE_IP" "if [ -d $TRACEPOINT_PATH ]; then
      echo 0 > $TRACEPOINT_PATH/enable;
      echo '' > $TRACEPOINT_PATH/$TRACEPOINT/trigger;
    else
      echo 'Error: Tracepoint $TRACEPOINT does not exist.';
      exit 1;
    fi" || {
      echo "Error: Failed to disable tracepoint $TRACEPOINT on target $DEVICE_IP."
      exit 1
    }
    ;;
  *)
    echo "Invalid option: $1"
    show_help
    exit 1
    ;;
esac

