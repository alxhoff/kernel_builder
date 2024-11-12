#!/bin/bash

# Display help information
if [[ "$1" == "--help" ]]; then
  echo "probe_camera_controls_formatted.sh - Lists and formats all adjustable controls for a v4l2 camera device."
  echo
  echo "Usage:"
  echo "  $0 [<device-ip>] <device>"
  echo
  echo "Description:"
  echo "  Connects to the target device via SSH, retrieves all adjustable controls for the specified"
  echo "  camera device using v4l2-ctl, and formats the output to show each control with its current"
  echo "  value, possible range/values, and whether it is writable."
  echo
  echo "Example:"
  echo "  $0 192.168.1.100 /dev/video0"
  exit 0
fi

# Set the script directory and device IP
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ "$#" -lt 2 ]; then
    echo "Usage: $0 [<device-ip>] <device>"
    exit 1
  fi
  DEVICE_IP=$1
fi

# Shift arguments if device IP was provided
if [ "$DEVICE_IP" == "$1" ]; then
  shift
fi

DEVICE=$1
USERNAME="root"

# Retrieve, format, and display controls for the specified camera device
ssh "$USERNAME@$DEVICE_IP" "v4l2-ctl -d '$DEVICE' --list-ctrls-menus" | awk '
BEGIN {
  print "---------------------------------------------------------------------------------------"
  print "| Control Name               | Current     | Range/Values                | Writable    |"
  print "---------------------------------------------------------------------------------------"
}
{
  # Capture control name and format it to fit within a specific width
  name = gensub(/\(.*$/, "", "g", $1)
  name = substr(name, 1, 25) # Limit name to 25 characters

  # Capture current value
  if (match($0, /value=([0-9]+)/, arr)) {
    value = arr[1]
  } else {
    value = "N/A"
  }

  # Capture range or menu options and format to fit column width
  if (match($0, /min=([0-9]+) max=([0-9]+)/, arr)) {
    range = "min=" arr[1] ", max=" arr[2]
  } else if (match($0, /\[(.+)\]/, arr)) {
    range = arr[1]
  } else {
    range = "N/A"
  }

  # Truncate range if it exceeds 25 characters
  if (length(range) > 25) {
    range = substr(range, 1, 22) "..."
  }

  # Check if writable
  writable = /writable/ ? "Yes" : "No"

  # Print formatted output
  printf "| %-25s | %-11s | %-25s | %-11s |\n", name, value, range, writable
}
END {
  print "---------------------------------------------------------------------------------------"
}'

