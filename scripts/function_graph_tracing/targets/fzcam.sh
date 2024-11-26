#!/bin/bash

# Wrapper script for tracing a single function in the fzcam module
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

# Pass through all arguments to trace_single_function.sh
"${SCRIPT_DIR}/trace_single_function.sh" --module fzcam --function fzcam_function "$@"

