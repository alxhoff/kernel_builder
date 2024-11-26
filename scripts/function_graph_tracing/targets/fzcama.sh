#!/bin/bash

# Wrapper script for tracing a single function in the fzcama module
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

# Pass through all arguments to trace_single_function.sh
"${SCRIPT_DIR}/trace_single_function.sh" --module fzcama --function fzcama_function "$@"

