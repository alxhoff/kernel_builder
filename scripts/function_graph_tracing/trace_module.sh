#!/bin/bash

# Trace a single function in a specified module
# Usage: ./trace_single_function.sh --module <module-name> --function <function-name> [--duration <seconds>] [--help]

DEFAULT_DURATION=30

SCRIPT_DIR="$(realpath "$(dirname "$0")")"

# Pass --help directly to the parent script
if [[ "$1" == "--help" || -z "$1" ]]; then
  cat << EOF
Usage: ./trace_single_function.sh --module <module-name> --function <function-name> [--duration <seconds>] [--help]

Description:
  This script traces a specific function within a kernel module.

Options:
  --module <module-name>   Name of the kernel module to trace (required).
  --function <function>    Name of the function to trace (required).
  --duration <seconds>     Duration of the trace (default: $DEFAULT_DURATION seconds).
  --help                   Show this help message.

Examples:
  Trace a single function for 30 seconds:
    ./trace_single_function.sh --module my_module --function my_function

  Trace a single function for 60 seconds:
    ./trace_single_function.sh --module my_module --function my_function --duration 60
EOF
  exit 0
fi

# Parse arguments
MODULE_NAME=""
FUNCTION_NAME=""
DURATION=$DEFAULT_DURATION

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --module) MODULE_NAME="$2"; shift ;;
    --function) FUNCTION_NAME="$2"; shift ;;
    --duration) DURATION="$2"; shift ;;
    --help) echo "Run './trace_single_function.sh --help' for usage."; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# Validate required parameters
if [[ -z "$MODULE_NAME" || -z "$FUNCTION_NAME" ]]; then
  echo "Error: --module <module-name> and --function <function> are required."
  exit 1
fi

# Call the parent script with mode "single" and the parsed arguments
"${SCRIPT_DIR}/trace_kernel.sh" single --module "$MODULE_NAME" --function "$FUNCTION_NAME" --duration "$DURATION"

