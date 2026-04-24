#!/bin/bash

# Wrapper: trace the vi_capture_control_message function in tegra-camrtc-capture-vi
# Usage: ./vi_capture_control_message.sh [--duration <seconds>]

SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

"${SCRIPT_DIR}/trace_single_function.sh" \
  --module tegra-camrtc-capture-vi \
  --function vi_capture_control_message \
  "$@"
