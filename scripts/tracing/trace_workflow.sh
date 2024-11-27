#!/bin/bash

# Simplified master workflow script

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
DEVICE_IP_FILE="$SCRIPT_DIR/../device_ip"

if [ -f "$DEVICE_IP_FILE" ]; then
  DEVICE_IP=$(cat "$DEVICE_IP_FILE")
else
  echo "Error: Device IP file not found."
  exit 1
fi

if [[ "$1" == "--help" ]]; then
  cat << EOF
Usage: $0 <duration_in_seconds> <tracepoint>

Description:
  Automates a tracing workflow on the target device.

Arguments:
  <duration_in_seconds>  Duration for tracing (default: 15 seconds).
  <tracepoint>           Tracepoint to trace (default: sched:sched_switch).

Examples:
  ./trace_workflow.sh 15 sched:sched_switch
  ./trace_workflow.sh 10 alex_trigger
EOF
  exit 0
fi

DURATION="${1:-15}"  # Default duration is 15 seconds
TRACEPOINT="${2:-sched:sched_switch}"  # Default tracepoint

echo "Preparing tracing environment..."
"$SCRIPT_DIR/prepare_tracing.sh"

echo "Setting filters (if needed)..."
"$SCRIPT_DIR/set_filter.sh" --modules my_module

echo "Enabling tracer..."
"$SCRIPT_DIR/manage_tracers.sh" --enable function_graph

echo "Enabling tracepoint: $TRACEPOINT..."
"$SCRIPT_DIR/tracepoints.sh" --enable "$TRACEPOINT"

echo "Starting tracing for $DURATION seconds..."
"$SCRIPT_DIR/control_tracing.sh" --start-duration "$DURATION"

echo "Retrieving logs..."
"$SCRIPT_DIR/retrieve_logs.sh" --output "trace_report_${TRACEPOINT}.txt"

echo "Tracing workflow completed. Logs saved to trace_report_${TRACEPOINT}.txt"

