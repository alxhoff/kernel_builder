#!/bin/bash

# Script to retrieve logs from /sys/fs/pstore on a Jetson device
# Usage: ./retrieve_pstore_logs.sh <destination-path> [<device-ip>] [<username>]
# Arguments:
#   <destination-path>  Path to save the logs on the local machine
#   [<device-ip>]       The IP address of the target Jetson device (optional if device_ip file exists)
#   [<username>]        The username for accessing the Jetson device (optional if device_username file exists, default: "root")

SCRIPT_DIR="$(realpath "$(dirname "$0")/../..")"

DESTINATION_PATH=$1

if [ -z "$DESTINATION_PATH" ]; then
  echo "Error: <destination-path> argument is required."
  exit 1
fi

# Check if device_ip file exists
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <destination-path> [<device-ip>] [<username>]"
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
    USERNAME="root"
  fi
fi

# Ensure the destination path exists
if [ ! -d "$DESTINATION_PATH" ]; then
  echo "Creating destination directory: $DESTINATION_PATH"
  mkdir -p "$DESTINATION_PATH"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to create destination directory $DESTINATION_PATH."
    exit 1
  fi
fi

# Retrieve logs from /sys/fs/pstore on the Jetson device
echo "Retrieving logs from /sys/fs/pstore on the Jetson device at $DEVICE_IP..."

SSH_COMMAND="ssh $USERNAME@$DEVICE_IP"
SCP_COMMAND="scp $USERNAME@$DEVICE_IP"

# Check if /sys/fs/pstore exists and retrieve logs
$SSH_COMMAND "[ -d /sys/fs/pstore ]" 2>/dev/null
if [ $? -ne 0 ]; then
  echo "Error: /sys/fs/pstore does not exist on the Jetson device at $DEVICE_IP."
  exit 1
fi

# List files in /sys/fs/pstore
FILES=$($SSH_COMMAND "ls /sys/fs/pstore" 2>/dev/null)

if [ -z "$FILES" ]; then
  echo "No logs found in /sys/fs/pstore on the Jetson device at $DEVICE_IP."
  exit 0
fi

# Copy files and append .log extension
for FILE in $FILES; do
  echo "Retrieving $FILE..."
  $SCP_COMMAND:/sys/fs/pstore/"$FILE" "$DESTINATION_PATH/$FILE.log"
  if [ $? -ne 0 ]; then
    echo "Failed to retrieve $FILE from the Jetson device."
  else
    echo "$FILE retrieved successfully."
  fi
done

echo "Logs successfully retrieved and saved to $DESTINATION_PATH."

