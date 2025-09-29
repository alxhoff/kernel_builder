#!/bin/bash

# Script to trace CAN driver functions with low overhead using ftrace/perf.
# Author: Gemini
# Date: 2025-09-18
# Modified: 2025-09-25 to reliably record for a set duration.

# --- Default Configuration ---
DURATION=1
TARGET_FUNCTION="m_can_do_rx_poll"
TARGET_TRACEPOINT="can:can_rx"
MODE=""

# --- Help/Usage Function ---
usage() {
    echo "Usage: $0 --mode [count|timestamp|perf|log] [options]"
    echo ""
    echo "A low-overhead tool to trace and count CAN message handling frequency."
    echo "Requires root privileges to run."
    echo ""
    echo "Modes:"
    echo "  --mode count        Counts how many times a kernel function is called. (Default)"
    echo "  --mode timestamp    Records high-precision timestamps for each function call."
    echo "  --mode perf         Uses the 'perf' tool to count a specific kernel tracepoint."
    echo "  --mode log          Traces a specific tracepoint and logs timestamps and IDs to messages.log."
    echo ""
    echo "Options:"
    echo "  -f, --function NAME   The kernel function to trace (default: '${TARGET_FUNCTION}')."
    echo "  -d, --duration SECS   The duration to trace in seconds (default: ${DURATION})."
    echo "  -t, --tracepoint NAME The tracepoint to use for 'perf' or 'log' mode (default: '${TARGET_TRACEPOINT}')."
    echo "  -h, --help            Display this help message."
    echo ""
    echo "Examples:"
    echo "  # Count how many times m_can_do_rx_poll is called in 5 seconds"
    echo "  sudo $0 --mode count --function m_can_do_rx_poll --duration 5"
    echo ""
    echo "  # Get timestamps for the TCAN interrupt handler for 1 second"
    echo "  sudo $0 --mode timestamp --function tcan4x5x_can_ist --duration 1"
    echo ""
    echo "  # Use perf to count received CAN frames on all interfaces for 3 seconds"
    echo "  sudo $0 --mode perf --duration 3"
    echo ""
    echo "  # Log CAN messages from 'm_can:m_can_receive_msg' for 10 seconds"
    echo "  sudo $0 --mode log --tracepoint m_can:m_can_receive_msg --duration 10"
    echo ""
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --mode) MODE="$2"; shift ;;
        -f|--function) TARGET_FUNCTION="$2"; shift ;;
        -d|--duration) DURATION="$2"; shift ;;
        -t|--tracepoint) TARGET_TRACEPOINT="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; usage; exit 1 ;;
    esac
    shift
done

# --- Sanity Checks ---
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Please use sudo."
   exit 1
fi

if [ -z "$MODE" ]; then
    echo "Error: --mode is a required argument."
    usage
    exit 1
fi

# --- Ftrace Setup Function ---
setup_ftrace() {
    TRACE_DIR="/sys/kernel/debug/tracing"
    if ! mount | grep -q ' /sys/kernel/debug ';
    then
        echo "Mounting debugfs..."
        mount -t debugfs none /sys/kernel/debug
    fi
    echo 0 > "${TRACE_DIR}/tracing_on" &>/dev/null
    echo nop > "${TRACE_DIR}/current_tracer"
    echo > "${TRACE_DIR}/trace"
    echo "Ftrace reset."
}

# --- Main Logic ---
case $MODE in
    count)
        echo "Mode: Counting calls to '${TARGET_FUNCTION}' for ${DURATION} second(s)..."
        setup_ftrace
        echo "${TARGET_FUNCTION}" > /sys/kernel/debug/tracing/set_ftrace_filter
        echo "function" > /sys/kernel/debug/tracing/current_tracer
        echo 1 > /sys/kernel/debug/tracing/tracing_on
        sleep "${DURATION}"
        echo 0 > /sys/kernel/debug/tracing/tracing_on

        COUNT=$(grep -c "${TARGET_FUNCTION}" /sys/kernel/debug/tracing/trace)
        FREQ=$(echo "$COUNT / $DURATION" | bc)

        echo "--------------------------------------------------"
        echo "Function '${TARGET_FUNCTION}' was called ${COUNT} times in ${DURATION} second(s)."
        echo "Average Frequency: ${FREQ} Hz"
        echo "--------------------------------------------------"
        ;;

    timestamp)
        echo "Mode: Recording timestamps for '${TARGET_FUNCTION}' for ${DURATION} second(s)..."
        if ! command -v trace-cmd &> /dev/null;
        then
            echo "Error: trace-cmd is not installed. Please install it with 'sudo apt install trace-cmd'."
            exit 1
        fi

        OUTPUT_FILE="trace.dat"
        echo "Capturing trace..."
        trace-cmd record -p function -l "${TARGET_FUNCTION}" -o "${OUTPUT_FILE}" sleep "${DURATION}" &>/dev/null

        echo "--------------------------------------------------"
        echo "Trace complete. Displaying report:"
        echo "--------------------------------------------------"
        trace-cmd report "${OUTPUT_FILE}"
        rm -f "${OUTPUT_FILE}"
        ;;

    perf)
        echo "Mode: Using perf to count '${TARGET_TRACEPOINT}' for ${DURATION} second(s)..."
        if ! command -v perf &> /dev/null;
        then
            echo "Error: perf is not installed. Please install it with 'sudo apt install linux-tools-common linux-tools-$(uname -r)'."
            exit 1
        fi

        echo "Starting perf stat... (Output will appear below)"
        echo "--------------------------------------------------"
        perf stat -e "${TARGET_TRACEPOINT}" -a sleep "${DURATION}"
        echo "--------------------------------------------------"
        ;;

    log)
        echo "Mode: Logging CAN messages from tracepoint '${TARGET_TRACEPOINT}' for ${DURATION} second(s)..."
        if ! command -v trace-cmd &> /dev/null;
        then
            echo "Error: trace-cmd is not installed. Please install it with 'sudo apt install trace-cmd'."
            exit 1
        fi

        OUTPUT_FILE="trace.dat"
        LOG_FILE="messages.log"
        
        echo "Capturing trace..."
        trace-cmd record -e "${TARGET_TRACEPOINT}" -o "${OUTPUT_FILE}" sleep "${DURATION}" &>/dev/null

        if [ ! -f "${OUTPUT_FILE}" ]; then
            echo "--------------------------------------------------"
            echo "Trace capture failed. The tracepoint '${TARGET_TRACEPOINT}' may be incorrect."
            echo "You can list available events with 'trace-cmd list -e'."
            echo "--------------------------------------------------"
            exit 1
        fi

        echo "--------------------------------------------------"
        echo "Trace complete. Processing log to '${LOG_FILE}'."
        echo "--------------------------------------------------"
        
        trace-cmd report "${OUTPUT_FILE}" | awk -v target_tp_full="${TARGET_TRACEPOINT}" -v target_tp="${TARGET_TRACEPOINT##*:}" \
            '{ 
                event_name = $4;
                sub(/:/, "", event_name);
            }
            event_name == target_tp {
                timestamp = $3;
                sub(/:/, "", timestamp);
                id_field = "N/A";
                netdev = "N/A";

                if (target_tp_full == "can:can_rx") {
                    netdev = $5;
                    id_field = $7;
                    sub(/#.*/, "", id_field);
                    id_field = "0x" id_field;
                } else if (target_tp_full == "m_can:m_can_receive_msg") {
                    netdev = $5;
                    id_part = $6;
                    split(id_part, parts, "=");
                    id_field = parts[2];
                } else {
                    # Portable generic parser for other tracepoints
                    for (i=5; i<=NF; i++) {
                        if (index($i, "id=") == 1 || index($i, "ID=") == 1) {
                            split($i, parts, "=");
                            id_field = parts[2];
                            break;
                        }
                    }
                }
                printf "Timestamp: %s, Interface: %s, Event: %s, Message ID: %s\n", timestamp, netdev, target_tp, id_field;
            }' > "${LOG_FILE}"

        if [ ! -s "${LOG_FILE}" ]; then
            echo "Warning: Log file is empty. The tracepoint may not have generated any events during the capture."
        else
            echo "Log saved to '${LOG_FILE}'. Showing first 10 lines:"
            head -n 10 "${LOG_FILE}"
        fi
        rm -f "${OUTPUT_FILE}"
        ;;

    *)
        echo "Error: Invalid mode '${MODE}'. Please choose 'count', 'timestamp', 'perf', or 'log'."
        usage
        exit 1
        ;;
esac
