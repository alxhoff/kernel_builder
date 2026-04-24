#!/bin/bash

# Trace all functions in a specified kernel module
# Usage: ./trace_module.sh --module <module-name> [--duration <seconds>] [--help]

DEFAULT_DURATION=30

SCRIPT_DIR="$(realpath "$(dirname "$0")")"

if [[ "$1" == "--help" || -z "$1" ]]; then
  cat << EOF
Usage: ./trace_module.sh --module <module-name> [--duration <seconds>] [--help]

Description:
  Traces all functions within a kernel module by forwarding to trace_kernel.sh
  in 'all' mode. Use trace_single_function.sh to trace one specific function.

Options:
  --module <module-name>   Name of the kernel module to trace (required).
  --duration <seconds>     Duration of the trace (default: $DEFAULT_DURATION seconds).
  --help                   Show this help message.

Examples:
  Trace every function in a module for 30 seconds:
    ./trace_module.sh --module my_module

  Trace every function in a module for 60 seconds:
    ./trace_module.sh --module my_module --duration 60
EOF
  exit 0
fi

MODULE_NAME=""
DURATION=$DEFAULT_DURATION

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --module) MODULE_NAME="$2"; shift ;;
    --duration) DURATION="$2"; shift ;;
    --help) echo "Run './trace_module.sh --help' for usage."; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

if [[ -z "$MODULE_NAME" ]]; then
  echo "Error: --module <module-name> is required."
  exit 1
fi

"${SCRIPT_DIR}/trace_kernel.sh" all --module "$MODULE_NAME" --duration "$DURATION"
