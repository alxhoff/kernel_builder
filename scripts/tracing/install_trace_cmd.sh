
if [[ "$1" == "--help" ]]; then
    echo "install_trace_cmd.sh Usage:"
    case "install_trace_cmd.sh" in
        "install_trace_cmd.sh")
            echo "Install trace-cmd tool for tracing kernel functionality."
            echo "Usage: ./install_trace_cmd.sh"
            ;;
        "list_tracepoints.sh")
            echo "List all available tracepoints in the kernel."
            echo "Usage: ./install_trace_cmd.sh"
            ;;
        "record_trace.sh")
            echo "Record a trace of kernel events."
            echo "Usage: ./install_trace_cmd.sh [duration_in_seconds]"
            echo "Example: ./install_trace_cmd.sh 10"
            ;;
        "report_trace.sh")
            echo "Generate a report from the recorded trace data."
            echo "Usage: ./install_trace_cmd.sh <trace_file>"
            echo "Example: ./install_trace_cmd.sh trace.dat"
            ;;
        "start_tracing.sh")
            echo "Start tracing kernel events."
            echo "Usage: ./install_trace_cmd.sh [duration_in_seconds]"
            echo "Example: ./install_trace_cmd.sh 10"
            ;;
        "start_tracing_system.sh")
            echo "Start system-wide tracing of kernel events."
            echo "Usage: ./install_trace_cmd.sh [duration_in_seconds]"
            echo "Example: ./install_trace_cmd.sh 10"
            ;;
        "stop_tracing.sh")
            echo "Stop the current kernel event tracing."
            echo "Usage: ./install_trace_cmd.sh"
            ;;
        "trace_workflow.sh")
            echo "Automate a full tracing workflow including start, record, stop, and report."
            echo "Usage: ./install_trace_cmd.sh [duration_in_seconds]"
            echo "Example: ./install_trace_cmd.sh 20"
            ;;
    esac
    exit 0
fi
#!/bin/bash

# Simple script to install trace-cmd on a Jetson device using kernel_debugger.py
# Usage: ./install_trace_cmd.sh [<device-ip>] [<username>]
# Arguments:
#   [<device-ip>]   The IP address of the target Jetson device (optional if device_ip file exists)
#   [<username>]    The username for accessing the Jetson device (optional if device_username file exists, default: "cartken")

# Get the path to the kernel_debugger.py script
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_DEBUGGER_PATH="$SCRIPT_DIR/../kernel_debugger.py"

# Check if device_ip file exists
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ "$#" -lt 1 ]; then
    echo "Usage: $0 [<device-ip>] [<username>]"
    exit 1
  fi
  DEVICE_IP=$1
fi

# Check if device_username file exists
if [ -f "$SCRIPT_DIR/device_username" ]; then
  USERNAME=$(cat "$SCRIPT_DIR/device_username")
else
  if [ "$#" -eq 2 ]; then
    USERNAME=$2
  else
    USERNAME="cartken"
  fi
fi

# Install trace-cmd on the Jetson device as root
echo "Installing trace-cmd on the Jetson device at $DEVICE_IP using kernel_debugger.py..."

python3 "$KERNEL_DEBUGGER_PATH" install-trace-cmd --ip "$DEVICE_IP" --user "$USERNAME"

if [ $? -eq 0 ]; then
  echo "trace-cmd installed successfully on the Jetson device at $DEVICE_IP"
else
  echo "Failed to install trace-cmd on the Jetson device at $DEVICE_IP"
  exit 1
fi

