#!/bin/bash

# Script to select specific tracepoints for tracing on NVIDIA Jetson devices

function show_help() {
    echo "Usage: $0 [--list | --enable <tracepoint> | --disable <tracepoint>]"
    echo
    echo "Options:"
    echo "  --list                 List all available tracepoints in the kernel."
    echo "  --enable <tracepoint>  Enable tracing for the specified tracepoint."
    echo "  --disable <tracepoint> Disable tracing for the specified tracepoint."
    echo
    echo "Examples:"
    echo "  $0 --list"
    echo "  $0 --enable sched:sched_switch"
    echo "  $0 --disable sched:sched_switch"
}

# Check if help is requested
if [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# Validate arguments
if [[ "$#" -lt 1 ]]; then
    echo "Error: Missing arguments."
    show_help
    exit 1
fi

# Parameters
option="$1"
tracepoint="$2"

# Functionality for listing or managing tracepoints
case "$option" in
    --list)
        echo "Listing all available tracepoints..."
        cat /sys/kernel/debug/tracing/available_events
        ;;
    --enable)
        if [[ -z "$tracepoint" ]]; then
            echo "Error: Missing tracepoint to enable."
            show_help
            exit 1
        fi
        echo 1 > /sys/kernel/debug/tracing/events/$tracepoint/enable
        echo "Enabled tracepoint: $tracepoint"
        ;;
    --disable)
        if [[ -z "$tracepoint" ]]; then
            echo "Error: Missing tracepoint to disable."
            show_help
            exit 1
        fi
        echo 0 > /sys/kernel/debug/tracing/events/$tracepoint/enable
        echo "Disabled tracepoint: $tracepoint"
        ;;
    *)
        echo "Error: Unknown option '$option'"
        show_help
        exit 1
        ;;
esac
