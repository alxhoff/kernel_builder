#!/bin/bash

# Wrapper script for tracing all functions in the tegra-camrtc-capture-vi module
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

# Pass through all arguments to trace_module.sh
"${SCRIPT_DIR}/trace_module.sh" --module tegra-camrtc-capture-vi "$@"

