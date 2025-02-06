#!/bin/bash

# Define the output file
OUTPUT_FILE="rtcpu_trace.txt"

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# Check if v4l2-ctl is installed
if ! command -v v4l2-ctl &> /dev/null; then
  echo "v4l2-ctl is not installed. Installing it now..."
  apt-get update && apt-get install -y v4l-utils
  if [[ $? -ne 0 ]]; then
    echo "Failed to install v4l2-ctl. Please install it manually and re-run the script." >&2
    exit 1
  fi
fi

# Enable tracing
echo 1 > /sys/kernel/debug/tracing/tracing_on

# Set the buffer size
echo 30720 > /sys/kernel/debug/tracing/buffer_size_kb

# Enable specific events
echo 1 > /sys/kernel/debug/tracing/events/tegra_rtcpu/enable
echo 1 > /sys/kernel/debug/tracing/events/freertos/enable
echo 3 > /sys/kernel/debug/camrtc/log-level
echo 1 > /sys/kernel/debug/tracing/events/camera_common/enable

# Clear the trace buffer
echo > /sys/kernel/debug/tracing/trace

# Start the V4L2 stream
v4l2-ctl --stream-mmap -c bypass_mode=0 &
STREAM_PID=$!

# Wait for 5 seconds
sleep 5

# Stop the V4L2 stream
kill $STREAM_PID

# Capture the trace to the output file
cat /sys/kernel/debug/tracing/trace > "$OUTPUT_FILE"

# Disable tracing
echo 0 > /sys/kernel/debug/tracing/tracing_on

# Notify the user
echo "Trace completed and saved to $OUTPUT_FILE"

