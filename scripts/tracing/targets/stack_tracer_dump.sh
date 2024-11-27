#!/bin/bash

# Script to trace the `stack_tracer:stack_tracer_dump` tracepoint

SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
TARGETS_DIR="$(realpath "$(dirname "$0")")"

DEVICE_IP_FILE="$SCRIPT_DIR/device_ip"

if [ -f "$DEVICE_IP_FILE" ]; then
  DEVICE_IP=$(cat "$DEVICE_IP_FILE")
else
  echo "Error: Device IP file not found."
  exit 1
fi

if [[ "$1" == "--help" ]]; then
  cat << EOF
Usage: $0 [--duration <seconds>] [--output <file>]

Description:
  Traces the 'stack_tracer:stack_tracer_dump' tracepoint on the target device, executing its fast_assign logic.

Options:
  --duration <seconds>  Specify the tracing duration (default: 15 seconds).
  --output <file>       Specify the output file for the logs (default: trace_stack_tracer.txt).

Examples:
  ./trace_stack_tracer.sh
  ./trace_stack_tracer.sh --duration 30
  ./trace_stack_tracer.sh --duration 10 --output stack_logs.txt
EOF
  exit 0
fi

# Default values
DURATION=15
OUTPUT_FILE="trace_stack_tracer.txt"

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --duration) DURATION="$2"; shift ;;
    --output) OUTPUT_FILE="$2"; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# Workflow
echo "Preparing tracing environment..."
"$SCRIPT_DIR/prepare_tracing.sh"

echo "Enabling tracepoint: stack_tracer:stack_tracer_dump..."
"$SCRIPT_DIR/tracepoints.sh" --enable stack_tracer:stack_tracer_dump

echo "Starting tracing for $DURATION seconds..."
"$SCRIPT_DIR/control_tracing.sh" --start-duration "$DURATION"

echo "Retrieving logs..."
"$SCRIPT_DIR/retrieve_logs.sh" --output "$OUTPUT_FILE"

echo "Disabling tracepoint: stack_tracer:stack_tracer_dump..."
"$SCRIPT_DIR/tracepoints.sh" --disable stack_tracer:stack_tracer_dump

echo "Tracing for 'stack_tracer:stack_tracer_dump' completed. Logs saved to $OUTPUT_FILE."

