#!/bin/bash

# A script to capture a kernel tracepoint and analyze the average time
# between sequential index values reported by that tracepoint.
# Author: Gemini
# Date: 2025-09-18 (Revised)

# --- Default Configuration ---
DURATION=2
TARGET_TRACEPOINT=""
KEEP_FILE=false

# --- Help/Usage Function ---
usage() {
    echo "Usage: $0 --tracepoint <name> --duration <seconds> [options]"
    echo ""
    echo "Captures trace events and calculates the average time between sequential"
    echo "index values (e.g., 0->1, 1->2, ... wrap-around)."
    echo "Must be run as root."
    echo ""
    echo "Required:"
    echo "  -t, --tracepoint NAME   The full name of the tracepoint (e.g., 'm_can:m_can_do_rx_poll_timing')."
    echo "  -d, --duration SECS     The duration to trace in seconds."
    echo ""
    echo "Options:"
    echo "  -k, --keep-file         Do not delete the raw trace capture file after analysis."
    echo "  -h, --help              Display this help message."
    echo ""
    echo "Example:"
    echo "  sudo $0 --tracepoint m_can:m_can_do_rx_poll_timing --duration 5 --keep-file"
    echo ""
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -t|--tracepoint) TARGET_TRACEPOINT="$2"; shift ;;
        -d|--duration) DURATION="$2"; shift ;;
        -k|--keep-file) KEEP_FILE=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; usage; exit 1 ;;
    esac
    shift
done

# --- Sanity Checks ---
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root." >&2
   exit 1
fi

if [ -z "$TARGET_TRACEPOINT" ] || [ -z "$DURATION" ]; then
    echo "Error: --tracepoint and --duration are required arguments." >&2
    usage
    exit 1
fi

TRACEPOINT_PATH=${TARGET_TRACEPOINT/:/\/}
ENABLE_FILE="/sys/kernel/debug/tracing/events/${TRACEPOINT_PATH}/enable"

if [ ! -f "$ENABLE_FILE" ]; then
    echo "Error: Tracepoint not found at ${ENABLE_FILE}" >&2
    exit 1
fi

# --- Cleanup function to ensure tracing is always disabled on exit ---
cleanup() {
    echo -e "\n--- Cleaning up: Disabling tracing ---" >&2
    echo 0 > /sys/kernel/debug/tracing/tracing_on 2>/dev/null
    echo 0 > "$ENABLE_FILE" 2>/dev/null
    # Remove the temp file if it exists, unless the user wants to keep it
    if [ "$KEEP_FILE" = false ] && [ -n "$CAPTURE_FILE" ] && [ -f "$CAPTURE_FILE" ]; then
        rm -f "$CAPTURE_FILE"
    fi
}
trap cleanup EXIT INT TERM

# --- Capture Logic ---
echo "--- Preparing tracer ---" >&2
echo 0 > /sys/kernel/debug/tracing/tracing_on
echo > /sys/kernel/debug/tracing/trace
echo 1 > "$ENABLE_FILE"

echo "--- Starting trace for ${DURATION} second(s)... ---" >&2
echo 1 > /sys/kernel/debug/tracing/tracing_on

sleep "$DURATION"

echo "--- Capture complete. Dumping and analyzing... ---" >&2
CAPTURE_FILE=$(mktemp)
cat /sys/kernel/debug/tracing/trace > "$CAPTURE_FILE"
echo "--- Raw trace data ---" >&2
cat "${CAPTURE_FILE}" >&2

# --- Analysis Logic ---
# Extract the event name (e.g., m_can_do_rx_poll_timing)
EVENT_NAME=$(echo "${TARGET_TRACEPOINT}" | cut -d':' -f2)

# Use awk to perform the timing analysis
ANALYSIS_RESULT=$(awk -v event="${EVENT_NAME}:" '
    # Main block: Process every line that contains our event
    $5 == event {
        # Extract timestamp and index value
        curr_ts = $4;
        gsub(/:/,"", curr_ts);
        split($NF, a, "=");
        curr_idx = a[2];

        # Find the maximum index value seen so far
        if (curr_idx > max_idx) { max_idx = curr_idx; }

        # If we have a previous data point, calculate the delta
        if (prev_ts > 0) {
            key = prev_idx "->" curr_idx;
            delta = curr_ts - prev_ts;

            # Ensure delta is positive (handles buffer wrap-around)
            if (delta > 0) {
                sum[key] += delta;
                count[key]++;
            }
        }

        # Store the current data point for the next iteration
        prev_ts = curr_ts;
        prev_idx = curr_idx;
    }

    # END block: After processing all lines, print the results
    END {
        if (max_idx < 0) {
            print "Error: No trace events were captured or parsed.";
            exit;
        }

        print "--------------------------------------------------";
        print "Trace Timing Analysis for '" event "'";
        print "--------------------------------------------------";

        # Print sequential timings (e.g., 0->1, 1->2)
        for (i = 0; i < max_idx; i++) {
            key = i "->" (i+1);
            if (count[key] > 0) {
                avg_s = sum[key] / count[key];
                printf "Avg time from index %d -> %d: %.3f µs (%d occurrences)\n", i, i+1, avg_s * 1000000, count[key];
            } else {
                printf "Avg time from index %d -> %d: No data\n", i, i+1;
            }
        }

        # Print wrap-around timing (max_idx -> 0)
        key = max_idx "->" 0;
        if (count[key] > 0) {
            avg_s = sum[key] / count[key];
            printf "Avg time from index %d -> %d: %.3f µs (%d occurrences)\n", max_idx, 0, avg_s * 1000000, count[key];
        } else {
            printf "Avg time from index %d -> %d: No data\n", max_idx, 0;
        }
        print "--------------------------------------------------";
    }
' "${CAPTURE_FILE}")

# Print the final formatted result
echo "${ANALYSIS_RESULT}"

if [ "$KEEP_FILE" = true ]; then
    echo -e "\nRaw trace data has been saved to: ${CAPTURE_FILE}"
fi


