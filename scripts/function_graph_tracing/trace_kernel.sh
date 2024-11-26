#!/bin/bash

# Main script to trace kernel functions
# Usage: ./trace_kernel.sh <mode> [--device-ip <ip-address>] [--module <module-name>] [--function <function-name>] [--duration <seconds>] [--help]

DEFAULT_DURATION=30

# Help Message
if [[ "$1" == "--help" || -z "$1" ]]; then
  cat << EOF
Usage: ./trace_kernel.sh <mode> [--device-ip <ip-address>] [--module <module-name>] [--function <function-name>] [--duration <seconds>] [--help]

Modes:
  all    Trace all functions in a module.
  single Trace a specific function in a module.

Options:
  --device-ip <ip-address>  IP address of the target device. Optional if a 'device_ip' file exists.
  --module <module-name>    Name of the kernel module to trace (required).
  --function <function>     Name of the function to trace (required for 'single' mode).
  --duration <seconds>      Duration of the trace (default: $DEFAULT_DURATION seconds).
  --help                    Show this help message.

Examples:
  Trace all functions in a module for 10 seconds:
    ./trace_kernel.sh all --device-ip 192.168.1.100 --module my_module --duration 10

  Trace a single function for 5 seconds:
    ./trace_kernel.sh single --device-ip 192.168.1.100 --module my_module --function my_function --duration 5
EOF
  exit 0
fi

SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

# Retrieve or parse device IP
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
  echo "Using device IP from file: $DEVICE_IP"
else
  if [[ "$1" == "--device-ip" && -n "$2" ]]; then
    DEVICE_IP=$2
    shift 2
    echo "Using provided device IP: $DEVICE_IP"
  else
    echo "Error: --device-ip <ip-address> is required if 'device_ip' file does not exist."
    exit 1
  fi
fi

# Parse Arguments
MODE=$1
shift
MODULE_NAME=""
FUNCTION_NAME=""
DURATION=$DEFAULT_DURATION

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --module) MODULE_NAME="$2"; shift ;;
    --function) FUNCTION_NAME="$2"; shift ;;
    --duration) DURATION="$2"; shift ;;
    --help) echo "Run './trace_kernel.sh --help' for usage."; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# Validate Required Parameters
if [[ -z "$MODULE_NAME" ]]; then
  echo "Error: --module <module-name> is required."
  exit 1
fi

TRACE_DIR="/sys/kernel/debug/tracing"
USERNAME="root"

# Verbose: Display inputs
echo "Mode: $MODE"
echo "Module: $MODULE_NAME"
[[ -n "$FUNCTION_NAME" ]] && echo "Function: $FUNCTION_NAME"
echo "Duration: $DURATION seconds"
echo "Target Device: $DEVICE_IP"

# Clear Previous Filters
echo "Clearing previous filters..."
ssh "$USERNAME@$DEVICE_IP" "echo '' > $TRACE_DIR/set_ftrace_filter" || {
  echo "Failed to clear filters. Check SSH connection or permissions."
  exit 1
}

case $MODE in
  all)
    echo "Adding all functions from module '$MODULE_NAME' to the trace filter..."
    ssh "$USERNAME@$DEVICE_IP" "echo '$MODULE_NAME:*' > $TRACE_DIR/set_ftrace_filter" || {
      echo "Failed to add module to filter. Verify module name."
      exit 1
    }
    ;;
  single)
    if [[ -z "$FUNCTION_NAME" ]]; then
      echo "Error: --function <function> is required for 'single' mode."
      exit 1
    fi
    echo "Adding function '$FUNCTION_NAME' from module '$MODULE_NAME' to the trace filter..."
    ssh "$USERNAME@$DEVICE_IP" "echo '$FUNCTION_NAME' > $TRACE_DIR/set_ftrace_filter" || {
      echo "Failed to add function to filter. Verify function name."
      exit 1
    }
    ;;
  *)
    echo "Invalid mode: $MODE. Use 'all' or 'single'."
    exit 1
    ;;
esac

# Start Tracing
echo "Clearing previous logs..."
ssh "$USERNAME@$DEVICE_IP" "echo > $TRACE_DIR/trace" || {
  echo "Failed to clear previous logs. Check permissions."
  exit 1
}

echo "Starting function graph tracing..."
ssh "$USERNAME@$DEVICE_IP" "echo 'function_graph' > $TRACE_DIR/current_tracer && echo 1 > $TRACE_DIR/tracing_on" || {
  echo "Failed to start tracing. Check tracer configuration."
  exit 1
}

if [[ "$DURATION" -gt 0 ]]; then
  echo "Tracing for $DURATION seconds..."
  sleep "$DURATION"
  echo "Stopping tracing..."
  ssh "$USERNAME@$DEVICE_IP" "echo 0 > $TRACE_DIR/tracing_on" || {
    echo "Failed to stop tracing. Check SSH connection."
    exit 1
  }
else
  read -p "Trigger the module functionality now, then press Enter to stop tracing..."
  ssh "$USERNAME@$DEVICE_IP" "echo 0 > $TRACE_DIR/tracing_on" || {
    echo "Failed to stop tracing. Check SSH connection."
    exit 1
  }
fi

# Fetch Trace Logs
TRACE_LOG="./trace_${MODE}_${MODULE_NAME}_${FUNCTION_NAME}.txt"
echo "Fetching trace logs..."
ssh "$USERNAME@$DEVICE_IP" "cat $TRACE_DIR/trace" > "$TRACE_LOG" || {
  echo "Failed to fetch trace logs. Check SSH connection or permissions."
  exit 1
}
echo "Trace log saved as $TRACE_LOG"

# Disable the Tracer
echo "Disabling tracing..."
ssh "$USERNAME@$DEVICE_IP" "echo '' > $TRACE_DIR/set_ftrace_filter" || {
  echo "Failed to disable tracing. Check SSH connection."
  exit 1
}

