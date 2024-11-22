#!/bin/bash

# Updated Trace Workflow Script for Jetson Devices
# This script uses the newly consolidated and updated scripts to automate the tracing workflow.

function show_help() {
    echo "Usage: $0 <duration_in_seconds>"
    echo
    echo "Automates the complete tracing workflow including starting the trace, recording data, stopping the trace,"
    echo "and generating a report."
    echo
    echo "Steps Involved:"
    echo "  1. Start System-wide Tracing: Initiates a system-wide trace for the specified duration using 'trace_entire_system.sh'."
    echo "     This step allows capturing a broad set of kernel events across the entire system."
    echo "  2. Record Trace Data: Uses 'trace.sh' to record the trace data into a file for further analysis."
    echo "     This step ensures that all relevant kernel events are saved to a file named 'trace.dat'."
    echo "  3. Stop Tracing: After recording, tracing is stopped using 'stop_tracing.sh' to ensure that no further events are logged."
    echo "  4. Generate Trace Report: Finally, the recorded trace data is processed using 'report_trace.sh' to generate a detailed report."
    echo
    echo "Example:"
    echo "  $0 20  # Automates the tracing workflow for 20 seconds"
}

# Check if help is requested
if [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# Validate arguments
if [[ "$#" -ne 1 ]]; then
    echo "Error: Invalid number of arguments."
    show_help
    exit 1
fi

# Validate duration
duration="$1"
if ! [[ "$duration" =~ ^[0-9]+$ ]]; then
    echo "Error: Duration must be a positive integer."
    exit 1
fi

# Start system-wide tracing
echo "Starting system-wide trace for $duration seconds..."
./trace_entire_system.sh "$duration"

# Record trace data for further analysis
echo "Recording kernel trace data..."
./trace.sh --record "$duration"

# Stop tracing
echo "Stopping tracing..."
./stop_tracing.sh

# Generate a trace report
trace_file="trace.dat"
if [[ -f "$trace_file" ]]; then
    echo "Generating trace report from $trace_file..."
    ./report_trace.sh "$trace_file"
else
    echo "Error: Trace file $trace_file not found."
    exit 1
fi

echo "Tracing workflow completed successfully."

