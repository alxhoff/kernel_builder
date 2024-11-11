#!/bin/bash

# Simple script to generate a trace report using kernel_debugger.py
# Usage: ./report_trace.sh <trace-file-path> <output-file>
# Arguments:
#   <trace-file-path>  Path to the trace.dat file on the host
#   <output-file>      Path to save the generated trace report

SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_DEBUGGER_PATH="$SCRIPT_DIR/../kernel_debugger.py"

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <trace-file-path> <output-file>"
  exit 1
fi

TRACE_FILE_PATH=$1
OUTPUT_FILE=$2

# Generate trace report
echo "Generating trace report using kernel_debugger.py..."

python3 "$KERNEL_DEBUGGER_PATH" report-trace --trace-file-path "$TRACE_FILE_PATH" --output-file "$OUTPUT_FILE"

if [ $? -eq 0 ]; then
  echo "Trace report generated successfully and saved to $OUTPUT_FILE"
else
  echo "Failed to generate trace report"
  exit 1
fi

