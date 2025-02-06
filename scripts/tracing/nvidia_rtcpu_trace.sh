#!/bin/bash

# Find script directory and read IP from parent directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
IP_FILE="$PARENT_DIR/device_ip"
# Ensure the IP file exists
if [[ ! -f "$IP_FILE" ]]; then
    echo "Error: IP file not found at $IP_FILE"
    exit 1
fi

# Read the IP address
TARGET_IP=$(cat "$IP_FILE" | tr -d '[:space:]')

# Default options
NO_V4L2=false

# Function to display help
function show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Runs Jetson RTCU tracing and optionally starts v4l2-ctl for 10 seconds."
    echo ""
    echo "Options:"
    echo "  --no-v4l2    Skip running v4l2-ctl and just wait 10 seconds."
    echo "  --help       Show this help message and exit."
    exit 0
}

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --no-v4l2)
            NO_V4L2=true
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Unknown option: $arg"
            show_help
            ;;
    esac
done

# Set output file name based on whether --no-v4l2 is used
if [[ "$NO_V4L2" == "true" ]]; then
    OUTPUT_FILE="rtcpu_cartken_webui.trace"
else
    OUTPUT_FILE="rtcpu.trace"
fi

# SSH command execution on the target device
SSH_CMD="ssh root@$TARGET_IP"

# Start tracing setup and clear logs
$SSH_CMD << EOF
echo 1 > /sys/kernel/debug/tracing/tracing_on
echo 30720 > /sys/kernel/debug/tracing/buffer_size_kb
echo 1 > /sys/kernel/debug/tracing/events/tegra_rtcpu/enable
echo 1 > /sys/kernel/debug/tracing/events/freertos/enable
echo 3 > /sys/kernel/debug/camrtc/log-level
echo 1 > /sys/kernel/debug/tracing/events/camera_common/enable

# Clear previous trace logs
echo > /sys/kernel/debug/tracing/trace
EOF

# Run v4l2-ctl in the background on the target, but return control to host
if [[ "$NO_V4L2" == "false" ]]; then
    echo "Starting v4l2-ctl on target..."
    $SSH_CMD "nohup v4l2-ctl --stream-mmap -c bypass_mode=0 > /dev/null 2>&1 & echo \$!" > v4l2_pid.txt
    V4L2_PID=$(cat v4l2_pid.txt)
    echo "v4l2-ctl running with PID $V4L2_PID on target."
else
    echo "Skipping v4l2-ctl, just waiting..."
fi

# Wait 10 seconds on the host
echo "Waiting 10 seconds..."
sleep 10

# Stop v4l2-ctl if it was started
if [[ "$NO_V4L2" == "false" ]]; then
    echo "Stopping v4l2-ctl on target..."
    $SSH_CMD "kill $V4L2_PID"
fi

# Retrieve trace log
echo "Fetching trace log..."
$SSH_CMD "cat /sys/kernel/debug/tracing/trace" > "$OUTPUT_FILE"

echo "Trace saved to $OUTPUT_FILE"

