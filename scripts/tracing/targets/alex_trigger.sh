#!/bin/bash

# Script to trace the 'alex_trigger' tracepoint

SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

TRACEPOINT="alex_trigger"
DURATION=2

# Display help
if [[ "$1" == "--help" ]]; then
  cat << EOF
Usage: ./alex_trigger.sh [--duration <seconds>]

Description:
  Sets up and traces the 'alex_trigger' tracepoint, capturing function calls leading to its activation.

Options:
  --duration <seconds>  Specify the duration for tracing (default: 30 seconds).

Examples:
  Trace 'alex_trigger' for the default duration:
    ./alex_trigger.sh

  Trace 'alex_trigger' for 60 seconds:
    ./alex_trigger.sh --duration 60
EOF
  exit 0
fi

# Parse optional duration argument
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --duration) DURATION="$2"; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# Trace the workflow using trace_workflow.sh
echo "${SCRIPT_DIR}/trace_workflow.sh" "$DURATION" "$TRACEPOINT"
"${SCRIPT_DIR}/trace_workflow.sh" "$DURATION" "$TRACEPOINT" || {
  echo "Error: Tracing workflow failed for tracepoint $TRACEPOINT."
  exit 1
}

echo "Tracing for '$TRACEPOINT' completed successfully."
