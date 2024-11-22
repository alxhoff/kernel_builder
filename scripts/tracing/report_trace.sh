
if [[ "$1" == "--help" ]]; then
    echo "report_trace.sh Usage:"
    case "report_trace.sh" in
        "install_trace_cmd.sh")
            echo "Install trace-cmd tool for tracing kernel functionality."
            echo "Usage: ./report_trace.sh"
            ;;
        "list_tracepoints.sh")
            echo "List all available tracepoints in the kernel."
            echo "Usage: ./report_trace.sh"
            ;;
        "record_trace.sh")
            echo "Record a trace of kernel events."
            echo "Usage: ./report_trace.sh [duration_in_seconds]"
            echo "Example: ./report_trace.sh 10"
            ;;
        "report_trace.sh")
            echo "Generate a report from the recorded trace data."
            echo "Usage: ./report_trace.sh <trace_file>"
            echo "Example: ./report_trace.sh trace.dat"
            ;;
        "start_tracing.sh")
            echo "Start tracing kernel events."
            echo "Usage: ./report_trace.sh [duration_in_seconds]"
            echo "Example: ./report_trace.sh 10"
            ;;
        "start_tracing_system.sh")
            echo "Start system-wide tracing of kernel events."
            echo "Usage: ./report_trace.sh [duration_in_seconds]"
            echo "Example: ./report_trace.sh 10"
            ;;
        "stop_tracing.sh")
            echo "Stop the current kernel event tracing."
            echo "Usage: ./report_trace.sh"
            ;;
        "trace_workflow.sh")
            echo "Automate a full tracing workflow including start, record, stop, and report."
            echo "Usage: ./report_trace.sh [duration_in_seconds]"
            echo "Example: ./report_trace.sh 20"
            ;;
    esac
    exit 0
fi
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

