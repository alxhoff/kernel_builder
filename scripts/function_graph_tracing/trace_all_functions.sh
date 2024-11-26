#!/bin/bash

# Trace all functions in a specified module
# Usage: ./trace_all_functions.sh --module <module-name> [--duration <seconds>] [--help]

DEFAULT_DURATION=30

SCRIPT_DIR="$(realpath "$(dirname "$0")")"

# Pass --help directly to the parent script
if [[ "$1" == "--help" || -z "$1" ]]; then
  cat << EOF
Usage: ./trace_all_functions.sh --module <module-name> [--duration <seconds>] [--help]

Description:
  This script traces all functions within a specified kernel module (wrapper for trace_module.sh).

Options:
  --module <module-name>   Name of the kernel module to trace (required).
  --duration <seconds>     Duration of the trace (default: $DEFAULT_DURATION seconds).
  --help                   Show this help message.

Examples:
  Trace all functions in a module for 30 seconds:
    ./trace_all_functions.sh --module my_module

  Trace all functions in a module for 60 seconds:
    ./trace_all_functions.sh --module my_module --duration 60
EOF
  exit 0
fi

# Call trace_module.sh with the same arguments
"${SCRIPT_DIR}/trace_module.sh" "$@"

