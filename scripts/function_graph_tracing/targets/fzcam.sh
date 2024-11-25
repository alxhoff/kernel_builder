#!/bin/bash

# Minimal script to trace fzcam using trace_module.sh
# Usage: ./trace_fzcam.sh [--duration <seconds>] [--help]

DEFAULT_DURATION=30

SCRIPT_DIR="$(realpath "$(dirname "$0")")"

# Pass --help directly to the parent script
if [[ "$1" == "--help" ]]; then
  "${SCRIPT_DIR}/trace_module.sh" --help
  exit 0
fi

# Parse optional duration argument
DURATION=$DEFAULT_DURATION
if [[ "$1" == "--duration" && -n "$2" ]]; then
  DURATION=$2
fi

# Call the generic script with the module name and duration
"${SCRIPT_DIR}/trace_module.sh" fzcam --duration "$DURATION"

