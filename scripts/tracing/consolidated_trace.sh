#!/bin/bash

# Consolidated script for tracing kernel events on NVIDIA Jetson devices
# This script can either record traces to a file for analysis or start a tracing session for real-time observation.

function show_help() {
    echo "Usage: $0 [--record <duration_in_seconds> | --start <duration_in_seconds>]"
    echo
    echo "Options:"
    echo "  --record <duration>   Record a trace of kernel events for the specified duration."
    echo "                        The trace data is saved for further analysis."
    echo "  --start <duration>    Start tracing kernel events for the specified duration without saving the trace."
    echo "                        Use this for real-time monitoring."
    echo
    echo "Examples:"
    echo "  $0 --record 10        Record trace data for 10 seconds and save to a file."
    echo "  $0 --start 10         Start tracing for 10 seconds for real-time observation (no saved output)."
}

# Check if help is requested
if [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# Validate arguments
if [[ "$#" -ne 2 ]]; then
    echo "Error: Invalid number of arguments."
    show_help
    exit 1
fi

# Parameters
option="$1"
duration="$2"

# Validate duration
if ! [[ "$duration" =~ ^[0-9]+$ ]]; then
    echo "Error: Duration must be a positive integer."
    exit 1
fi

# Consolidated functionality for recording or starting a trace
case "$option" in
    --record)
        echo "Recording kernel trace for $duration seconds..."
        trace-cmd record -e all -o trace.dat sleep "$duration"
        echo "Trace data saved to trace.dat"
        ;;
    --start)
        echo "Starting kernel trace for $duration seconds..."
        echo 1 > /sys/kernel/debug/tracing/tracing_on
        sleep "$duration"
        echo 0 > /sys/kernel/debug/tracing/tracing_on
        echo "Tracing complete."
        ;;
    *)
        echo "Error: Unknown option '$option'"
        show_help
        exit 1
        ;;
esac
