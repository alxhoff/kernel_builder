#!/bin/bash

# Script to trace CAN driver functions with low overhead using ftrace/perf.
# Author: Gemini
# Date: 2025-09-18
# Modified: 2025-09-29 to support multiple tracepoints.

# --- Default Configuration ---
DURATION=1
TARGET_FUNCTION="m_can_do_rx_poll"
TARGET_TRACEPOINTS=()
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
    echo "  --mode perf         Uses 'perf' to count kernel tracepoints."
    echo "  --mode log          Traces kernel tracepoints and logs formatted output."
    echo ""
    echo "Options:"
    echo "  -f, --function NAME   The kernel function to trace (default: '${TARGET_FUNCTION}')."
    echo "  -d, --duration SECS   The duration to trace in seconds (default: ${DURATION})."
    echo "  -t, --tracepoint NAME The tracepoint to use. Can be specified multiple times (default: 'can:can_rx')."
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
    echo "  sudo $0 --mode perf --tracepoint can:can_rx --duration 3"
    echo ""
    echo "  # Log two tracepoints simultaneously for 10 seconds"
    echo "  sudo $0 --mode log --tracepoint m_can:m_can_bulk_read_begin --tracepoint m_can:m_can_bulk_read_done --duration 10"
    echo ""
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --mode) MODE="$2"; shift ;;
        -f|--function) TARGET_FUNCTION="$2"; shift ;;
        -d|--duration) DURATION="$2"; shift ;;
        -t|--tracepoint) TARGET_TRACEPOINTS+=("$2"); shift ;;
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

# Set default tracepoints if none are provided for relevant modes
if [[ "$MODE" == "perf" || "$MODE" == "log" ]] && [ ${#TARGET_TRACEPOINTS[@]} -eq 0 ]; then
    TARGET_TRACEPOINTS=("can:can_rx")
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
        echo "Mode: Using perf to count '${TARGET_TRACEPOINTS[*]}' for ${DURATION} second(s)..."
        if ! command -v perf &> /dev/null;
        then
            echo "Error: perf is not installed. Please install it with 'sudo apt install linux-tools-common linux-tools-$(uname -r)'."
            exit 1
        fi

        PERF_EVENTS=()
        for tp in "${TARGET_TRACEPOINTS[@]}"; do
            PERF_EVENTS+=(-e "$tp")
        done

        echo "Starting perf stat... (Output will appear below)"
        echo "--------------------------------------------------"
        perf stat "${PERF_EVENTS[@]}" -a sleep "${DURATION}"
        echo "--------------------------------------------------"
        ;;

    log)
        echo "Mode: Logging from tracepoint(s) '${TARGET_TRACEPOINTS[*]}' for ${DURATION} second(s)..."
        if ! command -v trace-cmd &> /dev/null;
        then
            echo "Error: trace-cmd is not installed. Please install it with 'sudo apt install trace-cmd'."
            exit 1
        fi

        TRACE_CMD_EVENTS=()
        for tp in "${TARGET_TRACEPOINTS[@]}"; do
            TRACE_CMD_EVENTS+=(-e "$tp")
        done

        OUTPUT_FILE="trace.dat"
        LOG_FILE="messages.log"
        
        echo "Capturing trace..."
        trace-cmd record "${TRACE_CMD_EVENTS[@]}" -o "${OUTPUT_FILE}" sleep "${DURATION}" &>/dev/null

        if [ ! -f "${OUTPUT_FILE}" ]; then
            echo "--------------------------------------------------"
            echo "Trace capture failed. One or more tracepoints may be incorrect."
            echo "You can list available events with 'trace-cmd list -e'."
            echo "--------------------------------------------------"
            exit 1
        fi

        echo "--------------------------------------------------"
        echo "Trace complete. Processing log to '${LOG_FILE}'."
        echo "--------------------------------------------------"
        
        trace-cmd report "${OUTPUT_FILE}" | awk '
            {
                event_name = $4;
                sub(/:/, "", event_name);
                timestamp = $3;
                sub(/:/, "", timestamp);

                if (event_name == "m_can_bulk_read_begin") {
                    fgi_field = "N/A";
                    ffl_field = "N/A";
                    for (i=5; i<=NF; i++) {
                        if (index($i, "fgi=") == 1) {
                            split($i, parts, "=");
                            fgi_field = parts[2];
                        }
                        if (index($i, "ffl=") == 1) {
                            split($i, parts, "=");
                            ffl_field = parts[2];
                        }
                    }
                    printf "Timestamp: %s, Event: %s, fgi: %s, ffl: %s\n", timestamp, event_name, fgi_field, ffl_field;
                } else if (event_name == "m_can_bulk_read_done") {
                    pkts_field = "N/A";
                    for (i=5; i<=NF; i++) {
                        if (index($i, "pkts=") == 1) {
                            split($i, parts, "=");
                            pkts_field = parts[2];
                            break;
                        }
                    }
                    printf "Timestamp: %s, Event: %s, pkts: %s\n", timestamp, event_name, pkts_field;
                } else if (event_name == "can_rx") {
                    netdev = $5;
                    id_field = $7;
                    sub(/#.*/, "", id_field);
                    id_field = "0x" id_field;
                    printf "Timestamp: %s, Interface: %s, Event: %s, Message ID: %s\n", timestamp, netdev, event_name, id_field;
                } else if (event_name == "m_can_receive_msg") {
                    netdev = $5;
                    id_part = $6;
                    split(id_part, parts, "=");
                    id_field = parts[2];
                    printf "Timestamp: %s, Interface: %s, Event: %s, Message ID: %s\n", timestamp, netdev, event_name, id_field;
                }
            }
        ' > "${LOG_FILE}"

        if [ ! -s "${LOG_FILE}" ]; then
            echo "Warning: Log file is empty. The tracepoint(s) may not have generated any events during the capture."
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
