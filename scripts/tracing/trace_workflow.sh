
if [[ "$1" == "--help" ]]; then
    echo "trace_workflow.sh Usage:"
    case "trace_workflow.sh" in
        "install_trace_cmd.sh")
            echo "Install trace-cmd tool for tracing kernel functionality."
            echo "Usage: ./trace_workflow.sh"
            ;;
        "list_tracepoints.sh")
            echo "List all available tracepoints in the kernel."
            echo "Usage: ./trace_workflow.sh"
            ;;
        "record_trace.sh")
            echo "Record a trace of kernel events."
            echo "Usage: ./trace_workflow.sh [duration_in_seconds]"
            echo "Example: ./trace_workflow.sh 10"
            ;;
        "report_trace.sh")
            echo "Generate a report from the recorded trace data."
            echo "Usage: ./trace_workflow.sh <trace_file>"
            echo "Example: ./trace_workflow.sh trace.dat"
            ;;
        "start_tracing.sh")
            echo "Start tracing kernel events."
            echo "Usage: ./trace_workflow.sh [duration_in_seconds]"
            echo "Example: ./trace_workflow.sh 10"
            ;;
        "start_tracing_system.sh")
            echo "Start system-wide tracing of kernel events."
            echo "Usage: ./trace_workflow.sh [duration_in_seconds]"
            echo "Example: ./trace_workflow.sh 10"
            ;;
        "stop_tracing.sh")
            echo "Stop the current kernel event tracing."
            echo "Usage: ./trace_workflow.sh"
            ;;
        "trace_workflow.sh")
            echo "Automate a full tracing workflow including start, record, stop, and report."
            echo "Usage: ./trace_workflow.sh [duration_in_seconds]"
            echo "Example: ./trace_workflow.sh 20"
            ;;
    esac
    exit 0
fi
#!/bin/bash

# Trace workflow script for a Jetson device using trace-cmd
# Usage: ./trace_workflow.sh --tracepoints <tracepoints> [--duration <duration>] [--ip <device-ip>] [--user <username>] [--dry-run]

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_DEBUGGER_PATH="$SCRIPT_DIR/kernel_debugger.py"

# Default values
USERNAME="cartken"
DEVICE_IP=""

# Check if device_ip file exists in the script directory
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(<"$SCRIPT_DIR/device_ip")
fi

# Check if device_username file exists in the script directory
if [ -f "$SCRIPT_DIR/device_username" ]; then
  USERNAME=$(<"$SCRIPT_DIR/device_username")
fi

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --tracepoints) TRACEPOINTS="$2"; shift ;;
        --duration) DURATION="$2"; shift ;;
        --ip) DEVICE_IP="$2"; shift ;;
        --user) USERNAME="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Check mandatory arguments
if [ -z "$TRACEPOINTS" ]; then
    echo "Usage: $0 --tracepoints <tracepoints> [--duration <duration>] [--ip <device-ip>] [--user <username>] [--dry-run]"
    exit 1
fi

# Ensure DEVICE_IP is set
if [ -z "$DEVICE_IP" ]; then
  echo "Error: Device IP address must be provided either via --ip argument or 'device_ip' file."
  exit 1
fi

# Install trace-cmd on the device
echo "Installing trace-cmd on the Jetson device at $DEVICE_IP..."
python3 "$KERNEL_DEBUGGER_PATH" install-trace-cmd --ip "$DEVICE_IP" --user "$USERNAME" ${DRY_RUN:+--dry-run}
if [ $? -ne 0 ]; then
    echo "Failed to install trace-cmd on the Jetson device at $DEVICE_IP"
    exit 1
fi

# Start tracing the specified tracepoints
echo "Starting tracing for events ($TRACEPOINTS) on the Jetson device at $DEVICE_IP..."
python3 "$KERNEL_DEBUGGER_PATH" start-tracing --ip "$DEVICE_IP" --user "$USERNAME" --events "$TRACEPOINTS" ${DRY_RUN:+--dry-run}
if [ $? -ne 0 ]; then
    echo "Failed to start tracing on the Jetson device at $DEVICE_IP"
    exit 1
fi

# Record the trace with optional duration
echo "Recording trace on the Jetson device at $DEVICE_IP..."
python3 "$KERNEL_DEBUGGER_PATH" record-trace --ip "$DEVICE_IP" --user "$USERNAME" --trace-options "-e $TRACEPOINTS" ${DURATION:+--duration "$DURATION"} ${DRY_RUN:+--dry-run}
if [ $? -ne 0 ]; then
    echo "Failed to record trace on the Jetson device at $DEVICE_IP"
    exit 1
fi

# Stop tracing
echo "Stopping tracing on the Jetson device at $DEVICE_IP..."
python3 "$KERNEL_DEBUGGER_PATH" stop-tracing --ip "$DEVICE_IP" --user "$USERNAME" ${DRY_RUN:+--dry-run}
if [ $? -ne 0 ]; then
    echo "Failed to stop tracing on the Jetson device at $DEVICE_IP"
    exit 1
fi

# Retrieve the trace data from the Jetson device to the host
TRACE_FILE_PATH="/tmp/trace.dat"
echo "Retrieving trace data from the Jetson device at $DEVICE_IP to $TRACE_FILE_PATH..."
python3 "$KERNEL_DEBUGGER_PATH" retrieve-trace --ip "$DEVICE_IP" --user "$USERNAME" --destination-path "$TRACE_FILE_PATH" ${DRY_RUN:+--dry-run}
if [ $? -ne 0 ]; then
    echo "Failed to retrieve trace data from the Jetson device at $DEVICE_IP"
    exit 1
fi

# Generate a human-readable report from the trace.dat file
OUTPUT_REPORT_PATH="/tmp/trace_report.txt"
echo "Generating trace report at $OUTPUT_REPORT_PATH..."
python3 "$KERNEL_DEBUGGER_PATH" report-trace --trace-file-path "$TRACE_FILE_PATH" --output-file "$OUTPUT_REPORT_PATH" ${DRY_RUN:+--dry-run}
if [ $? -ne 0 ]; then
    echo "Failed to generate trace report"
    exit 1
fi

echo "Trace report successfully generated at $OUTPUT_REPORT_PATH"

