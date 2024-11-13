#!/bin/bash

# Usage: ./setup_function_graph_tracing.sh [<device-ip>] [--start-trace] [--stop-trace] [--duration <seconds>] [--dry-run] [--help]
# Options:
#   <device-ip>       The IP address of the remote Jetson device (required unless device_ip file is present).
#   --start-trace     Starts function graph tracing.
#   --stop-trace      Stops function graph tracing.
#   --duration <sec>  Runs the trace for a specified duration before stopping automatically.
#   --dry-run         Simulate the operations without making actual changes.
#   --help            Shows this help message with verbose explanation of each step.

# Extended Help: If --help is provided, a detailed description of each feature will be provided
if [[ "$1" == "--help" ]]; then
  cat << EOF

This script sets up and manages function graph tracing on a Linux system with ftrace enabled (e.g., on a Jetson device).
Function graph tracing is a powerful way to see what functions are being called in the kernel, along with their entry
and exit points. This can help debug kernel performance issues or verify that certain kernel functions are executed.

Prerequisites:
  - Root permissions are required to write into the tracefs (ftrace) system.
  - The kernel must be compiled with CONFIG_FTRACE and CONFIG_FUNCTION_GRAPH_TRACER enabled.
  - SSH access to the target device is required if using the script remotely.

Usage:
  ./setup_function_graph_tracing.sh [<device-ip>] [--start-trace] [--stop-trace] [--duration <seconds>] [--dry-run] [--help]

Options:
  <device-ip>       The IP address of the remote Jetson device (required unless device_ip file is present).
  --start-trace     Starts function graph tracing.
  --stop-trace      Stops function graph tracing.
  --duration <sec>  Runs the trace for a specified duration before stopping automatically.
  --dry-run         Simulate the operations without making actual changes.
  --help            Shows this help message with verbose explanation of each step.

Examples of Use:
1. **Start tracing and stop manually**:
   ```bash
   sudo ./setup_function_graph_tracing.sh <device-ip> --start-trace
   ```
   This will start function graph tracing and keep it running. You can then stop the trace by running:
   ```bash
   sudo ./setup_function_graph_tracing.sh <device-ip> --stop-trace
   ```

2. **Start tracing for a fixed duration**:
   ```bash
   sudo ./setup_function_graph_tracing.sh <device-ip> --start-trace --duration 10
   ```
   This will run the tracing for 10 seconds and then stop automatically, after which you can check the output.

3. **Stop tracing and output the results**:
   If tracing is already running, you can stop it and see the trace by executing:
   ```bash
   sudo ./setup_function_graph_tracing.sh <device-ip> --stop-trace
   ```

4. **View help information**:
   To understand the script's options:
   ```bash
   ./setup_function_graph_tracing.sh --help
   ```

5. **Simulate operations without making changes (dry-run)**:
   To simulate the script without applying any changes, use the --dry-run flag. For example:
   ```bash
   sudo ./setup_function_graph_tracing.sh <device-ip> --start-trace --dry-run
   ```

EOF
  exit 0
fi

# Set the script directory and device IP
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
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
USERNAME="root"

# Verify root privileges since the tracing requires it.
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Please run it again with sudo."
  exit 1
fi

# Base directory for tracing on the remote device
TRACE_DIR="/sys/kernel/debug/tracing"

# Ensure tracing directory exists on remote device
if ! ssh "$USERNAME@$DEVICE_IP" "test -d $TRACE_DIR"; then
  echo "Error: Tracefs directory '$TRACE_DIR' does not exist on remote device. Make sure the kernel is configured with tracing support."
  exit 1
fi

# Parse Arguments
START_TRACE=false
STOP_TRACE=false
DURATION=0
DRY_RUN=false

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --start-trace)
      START_TRACE=true
      ;;
    --stop-trace)
      STOP_TRACE=true
      ;;
    --duration)
      if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
        DURATION=$2
        shift
      else
        echo "Error: --duration requires a positive integer value."
        exit 1
      fi
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    *)
      echo "Unknown parameter: $1"
      exit 1
      ;;
  esac
  shift
done

# Start Function Graph Tracing
if [ "$START_TRACE" == true ]; then
  echo "Setting up function graph tracing on remote device $DEVICE_IP..."

  if [ "$DRY_RUN" == true ]; then
    echo "[Dry-run] Would enable function graph tracer on remote device."
    echo "[Dry-run] Would set tracing on to 1 on remote device."
  else
    # Enable function graph tracer on the remote device
    ssh "$USERNAME@$DEVICE_IP" "echo 'function_graph' > $TRACE_DIR/current_tracer"
    echo "Enabled function graph tracer on remote device."

    # Set options for verbose output and start tracing
    ssh "$USERNAME@$DEVICE_IP" "echo 1 > $TRACE_DIR/tracing_on"
    echo "Tracing is now ON on remote device."
  fi

  # If duration is provided, automatically stop tracing after the specified time
  if [ "$DURATION" -gt 0 ]; then
    echo "Recording trace for $DURATION seconds on remote device..."
    if [ "$DRY_RUN" == false ]; then
      sleep "$DURATION"
      ssh "$USERNAME@$DEVICE_IP" "echo 0 > $TRACE_DIR/tracing_on"
      echo "Tracing has been stopped after $DURATION seconds on remote device."
    else
      echo "[Dry-run] Would sleep for $DURATION seconds and then stop tracing."
    fi
  else
    echo "Tracing is running on remote device. Use --stop-trace to stop it manually."
  fi
fi

# Stop Function Graph Tracing
if [ "$STOP_TRACE" == true ]; then
  echo "Stopping function graph tracing on remote device $DEVICE_IP..."

  if [ "$DRY_RUN" == true ]; then
    echo "[Dry-run] Would disable tracing on remote device."
    echo "[Dry-run] Would output the trace log from remote device."
  else
    # Disable tracing on the remote device
    ssh "$USERNAME@$DEVICE_IP" "echo 0 > $TRACE_DIR/tracing_on"
    echo "Tracing is now OFF on remote device."

    # Output the trace results from the remote device
    echo "Outputting the trace log from remote device $DEVICE_IP:"
    ssh "$USERNAME@$DEVICE_IP" "cat $TRACE_DIR/trace"
  fi
fi

