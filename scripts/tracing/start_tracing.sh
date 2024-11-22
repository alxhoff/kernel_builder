
if [[ "$1" == "--help" ]]; then
    echo "start_tracing.sh Usage:"
    case "start_tracing.sh" in
        "install_trace_cmd.sh")
            echo "Install trace-cmd tool for tracing kernel functionality."
            echo "Usage: ./start_tracing.sh"
            ;;
        "list_tracepoints.sh")
            echo "List all available tracepoints in the kernel."
            echo "Usage: ./start_tracing.sh"
            ;;
        "record_trace.sh")
            echo "Record a trace of kernel events."
            echo "Usage: ./start_tracing.sh [duration_in_seconds]"
            echo "Example: ./start_tracing.sh 10"
            ;;
        "report_trace.sh")
            echo "Generate a report from the recorded trace data."
            echo "Usage: ./start_tracing.sh <trace_file>"
            echo "Example: ./start_tracing.sh trace.dat"
            ;;
        "start_tracing.sh")
            echo "Start tracing kernel events."
            echo "Usage: ./start_tracing.sh [duration_in_seconds]"
            echo "Example: ./start_tracing.sh 10"
            ;;
        "start_tracing_system.sh")
            echo "Start system-wide tracing of kernel events."
            echo "Usage: ./start_tracing.sh [duration_in_seconds]"
            echo "Example: ./start_tracing.sh 10"
            ;;
        "stop_tracing.sh")
            echo "Stop the current kernel event tracing."
            echo "Usage: ./start_tracing.sh"
            ;;
        "trace_workflow.sh")
            echo "Automate a full tracing workflow including start, record, stop, and report."
            echo "Usage: ./start_tracing.sh [duration_in_seconds]"
            echo "Example: ./start_tracing.sh 20"
            ;;
    esac
    exit 0
fi
#!/bin/bash

# Simple script to start tracing events on a Jetson device using kernel_debugger.py
# Usage: ./start_tracing.sh <events> [<device-ip>] [<username>]
# Arguments:
#   <events>        The events to start tracing
#   [<device-ip>]   The IP address of the target Jetson device (optional if device_ip file exists)
#   [<username>]    The username for accessing the Jetson device (optional if device_username file exists, default: "cartken")

# Get the path to the kernel_debugger.py script
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_DEBUGGER_PATH="$SCRIPT_DIR/../kernel_debugger.py"

EVENTS=$1

# Check if device_ip file exists
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <events> [<device-ip>] [<username>]"
    exit 1
  fi
  DEVICE_IP=$2
fi

# Check if device_username file exists
if [ -f "$SCRIPT_DIR/device_username" ]; then
  USERNAME=$(cat "$SCRIPT_DIR/device_username")
else
  if [ "$#" -eq 3 ]; then
    USERNAME=$3
  else
    USERNAME="cartken"
  fi
fi

# Start tracing events on the Jetson device
echo "Starting tracing on the Jetson device at $DEVICE_IP using kernel_debugger.py..."

python3 "$KERNEL_DEBUGGER_PATH" start-tracing --ip "$DEVICE_IP" --user "$USERNAME" --events "$EVENTS"

if [ $? -eq 0 ]; then
  echo "Tracing started successfully on the Jetson device at $DEVICE_IP"
else
  echo "Failed to start tracing on the Jetson device at $DEVICE_IP"
  exit 1
fi

