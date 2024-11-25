#!/bin/bash

# Minimal script to trace vi_capture_control_message using trace_function.sh
# Usage: ./trace_vi_capture_control_message.sh [--duration <seconds>]

DEFAULT_DURATION=30
SCRIPT_DIR="$(realpath "$(dirname "$0")")"

# Parse optional duration argument
DURATION=$DEFAULT_DURATION
if [[ "$1" == "--duration" && -n "$2" ]]; then
  DURATION=$2
fi

# Call the generic function tracing script with the function name and duration
"${SCRIPT_DIR}/trace_function.sh" vi_capture_control_message --duration "$DURATION"

