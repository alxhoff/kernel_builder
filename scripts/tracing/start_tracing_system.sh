
if [[ "$1" == "--help" ]]; then
    echo "start_tracing_system.sh Usage:"
    case "start_tracing_system.sh" in
        "install_trace_cmd.sh")
            echo "Install trace-cmd tool for tracing kernel functionality."
            echo "Usage: ./start_tracing_system.sh"
            ;;
        "list_tracepoints.sh")
            echo "List all available tracepoints in the kernel."
            echo "Usage: ./start_tracing_system.sh"
            ;;
        "record_trace.sh")
            echo "Record a trace of kernel events."
            echo "Usage: ./start_tracing_system.sh [duration_in_seconds]"
            echo "Example: ./start_tracing_system.sh 10"
            ;;
        "report_trace.sh")
            echo "Generate a report from the recorded trace data."
            echo "Usage: ./start_tracing_system.sh <trace_file>"
            echo "Example: ./start_tracing_system.sh trace.dat"
            ;;
        "start_tracing.sh")
            echo "Start tracing kernel events."
            echo "Usage: ./start_tracing_system.sh [duration_in_seconds]"
            echo "Example: ./start_tracing_system.sh 10"
            ;;
        "start_tracing_system.sh")
            echo "Start system-wide tracing of kernel events."
            echo "Usage: ./start_tracing_system.sh [duration_in_seconds]"
            echo "Example: ./start_tracing_system.sh 10"
            ;;
        "stop_tracing.sh")
            echo "Stop the current kernel event tracing."
            echo "Usage: ./start_tracing_system.sh"
            ;;
        "trace_workflow.sh")
            echo "Automate a full tracing workflow including start, record, stop, and report."
            echo "Usage: ./start_tracing_system.sh [duration_in_seconds]"
            echo "Example: ./start_tracing_system.sh 20"
            ;;
    esac
    exit 0
fi
#!/bin/bash

# Script to start tracing all events from a specified system on a Jetson device
# Usage: ./start_tracing_system.sh <system-name> [device-ip] [device-username]

SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_DEBUGGER_PATH="$SCRIPT_DIR/../kernel_debugger.py"

# Get system name as the first argument
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <system-name> [device-ip] [device-username]"
  exit 1
fi

SYSTEM_NAME=$1

# Determine the device IP
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
elif [ -n "$2" ]; then
  DEVICE_IP=$2
else
  echo "Error: Device IP not specified."
  exit 1
fi

# Determine the device username
if [ -f "$SCRIPT_DIR/device_username" ]; then
  DEVICE_USERNAME=$(cat "$SCRIPT_DIR/device_username")
elif [ -n "$3" ]; then
  DEVICE_USERNAME=$3
else
  DEVICE_USERNAME="cartken"  # Default username
fi

# Start tracing all events under the specified system
python3 "$KERNEL_DEBUGGER_PATH" start-tracing --ip "$DEVICE_IP" --user "$DEVICE_USERNAME" --events "$SYSTEM_NAME"

