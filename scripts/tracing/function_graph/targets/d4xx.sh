#!/bin/bash

# Wrapper script for tracing all functions in the d4xx module
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

# Pass through all arguments to trace_module.sh
"${SCRIPT_DIR}/trace_module.sh" --module d4xx "$@"

