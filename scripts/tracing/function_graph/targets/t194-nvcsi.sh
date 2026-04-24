#!/bin/bash

# Wrapper script for tracing all functions in the t194-nvcsi module
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

# Pass through all arguments to trace_module.sh
"${SCRIPT_DIR}/trace_module.sh" --module t194-nvcsi "$@"

