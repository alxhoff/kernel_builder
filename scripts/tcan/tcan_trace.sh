#!/bin/bash

# Script to trace CAN driver functions with low overhead using ftrace/perf.
# Author: Gemini
# Date: 2025-09-18
# Modified: 2025-09-25 to add log mode and fix timestamp mode.

# --- Default Configuration ---
DURATION=1
TARGET_FUNCTION="m_can_do_rx_poll"
TARGET_TRACEPOINT="can:can_rx"
ADDITIONAL_TRACEPOINT="can:m_can_receive_msg" # Added for the new log mode
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
    echo "  --mode log          Traces CAN messages from specified tracepoints and logs timestamps and IDs to messages.log."
    echo ""
    echo "Options:"
    echo "  -f, --function NAME   The kernel function to trace (default: '${TARGET_FUNCTION}')."
    echo "  -d, --duration SECS   The duration to trace in seconds (default: ${DURATION})."
    echo "  -t, --tracepoint NAME The perf tracepoint to count (default: '${TARGET_TRACEPOINT}')."
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
    echo "  # Log CAN RX and m_can_receive_msg tracepoints for 10 seconds"
    echo "  sudo $0 --mode log --duration 10"
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
    if ! mount | grep -q ' /sys/kernel/debug '; then
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
        if ! command -v trace-cmd &> /dev/null; then
            echo "Error: trace-cmd is not installed. Please install it with 'sudo apt install trace-cmd'."
            exit 1
        fi

        OUTPUT_FILE="trace.dat"
        echo "Capturing trace... Output will be in '${OUTPUT_FILE}'."
        # The -d/--duration option is not standard in trace-cmd record.
        # Running in background and stopping with kill is more portable.
        trace-cmd record -p function -l "${TARGET_FUNCTION}" -o "${OUTPUT_FILE}" &
        TRACE_PID=$!
        sleep "${DURATION}"
        kill "${TRACE_PID}" &>/dev/null
        wait "${TRACE_PID}" 2>/dev/null


        echo "--------------------------------------------------"
        echo "Trace complete. Displaying report:"
        echo "--------------------------------------------------"
        trace-cmd report "${OUTPUT_FILE}"
        rm -f "${OUTPUT_FILE}"
        ;;

    perf)
        echo "Mode: Using perf to count '${TARGET_TRACEPOINT}' for ${DURATION} second(s)..."
        if ! command -v perf &> /dev/null; then
            echo "Error: perf is not installed. Please install it with 'sudo apt install linux-tools-common linux-tools-$(uname -r)'."
            exit 1
        fi

        echo "Starting perf stat... (Output will appear below)"
        echo "--------------------------------------------------"
        perf stat -e "${TARGET_TRACEPOINT}" -a sleep "${DURATION}"
        echo "--------------------------------------------------"
        ;;

    log)
        echo "Mode: Logging CAN messages from tracepoints for ${DURATION} second(s)..."
        if ! command -v trace-cmd &> /dev/null; then
            echo "Error: trace-cmd is not installed. Please install it with 'sudo apt install trace-cmd'."
            exit 1
        fi

        OUTPUT_FILE="trace.dat"
        LOG_FILE="messages.log"
        
        echo "Capturing trace for '${TARGET_TRACEPOINT}' and '${ADDITIONAL_TRACEPOINT}'..."
        trace-cmd record -e "${TARGET_TRACEPOINT}" -e "${ADDITIONAL_TRACEPOINT}" -o "${OUTPUT_FILE}" &
        TRACE_PID=$!
        sleep "${DURATION}"
        kill "${TRACE_PID}" &>/dev/null
        wait "${TRACE_PID}" 2>/dev/null

        echo "--------------------------------------------------"
        echo "Trace complete. Processing log to '${LOG_FILE}'."
        echo "--------------------------------------------------"
        
        trace-cmd report "${OUTPUT_FILE}" | awk -v target_tp="${TARGET_TRACEPOINT##*:}" -v additional_tp="${ADDITIONAL_TRACEPOINT##*:}" '
            {
                event_name = $4;
                sub(/:/, "", event_name);
            }
            event_name == target_tp {
                # Format for can:can_rx: ... timestamp: can:can_rx: can0 RX 123#...
                timestamp = $3;
                sub(/:/, "", timestamp);
                id_field = $7;
                sub(/#.*/, "", id_field);
                printf "Timestamp: %s, Event: %s, Message ID: 0x%s
", timestamp, target_tp, id_field;
            }
            event_name == additional_tp {
                # This part assumes a format for m_can_receive_msg.
                # It looks for "id=HEX" or "ID=HEX" in the trace line.
                timestamp = $3;
                sub(/:/, "", timestamp);
                id_field = "N/A";
                for (i=5; i<=NF; i++) {
                    if (match($i, /(id|ID)=([0-9a-fA-Fx]+)/, arr)) {
                        id_field = arr[2];
                        break;
                    }
                }
                printf "Timestamp: %s, Event: %s, Message ID: %s
", timestamp, additional_tp, id_field;
            }
        ' > "${LOG_FILE}"

        echo "Log saved to '${LOG_FILE}'. Showing first 10 lines:"
        head -n 10 "${LOG_FILE}"
        rm -f "${OUTPUT_FILE}"
        ;;

    *)
        echo "Error: Invalid mode '${MODE}'. Please choose 'count', 'timestamp', 'perf', or 'log'."
        usage
        exit 1
        ;;
esac