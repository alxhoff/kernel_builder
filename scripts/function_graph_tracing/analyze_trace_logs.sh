#!/bin/bash

# Automated Log Analysis for Function Graph Tracing
# Usage: ./analyze_trace_logs.sh <trace-log-file>

if [[ "$1" == "--help" || -z "$1" ]]; then
  cat << EOF
Usage: ./analyze_trace_logs.sh <trace-log-file>

Description:
  This script parses and summarizes trace logs generated by function graph tracing. It highlights:
    - Long-running functions (sorted by execution time).
    - Nested function calls with their hierarchy.

Parameters:
  <trace-log-file>  Path to the trace log file to analyze.

Output:
  1. A summary of the longest-running functions (execution time in microseconds).
  2. A detailed hierarchy of nested calls for easier debugging.

Examples:
  Analyze a trace log file:
    ./analyze_trace_logs.sh trace_log.txt
EOF
  exit 0
fi

TRACE_LOG="$1"

awk '/=>/ { gsub("\\[|\\]", "", $3); print $3, $NF }' "$TRACE_LOG" | sort -k2 -nr | head -20 > long_running_functions.txt
awk '/=>|<=/ { print gensub("=>", "ENTER", "g", $0); print gensub("<=.*", "EXIT", "g", $0); }' "$TRACE_LOG" > function_hierarchy.txt

echo "Analysis complete. See long_running_functions.txt and function_hierarchy.txt."

