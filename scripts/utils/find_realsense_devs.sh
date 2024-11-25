#!/bin/bash

# Determine the script directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

# Get the device IP
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ "$#" -lt 1 ]; then
    echo "Usage: $0 [--help] <device-ip>"
    exit 1
  fi
  DEVICE_IP=$1
fi

# Show help message
if [[ "$1" == "--help" ]]; then
  echo "Usage: $0 [--help] <device-ip>"
  echo
  echo "This script inspects RealSense cameras on the target device via SSH by analysing /proc/device-tree."
  echo
  echo "Options:"
  echo "  --help       Show this help message and exit."
  echo
  echo "Arguments:"
  echo "  <device-ip>  IP address of the target device. Required unless a device_ip file exists."
  exit 0
fi

# SSH username
SSH_USER="root"

# Inspection script for the target device
INSPECTION_SCRIPT="/tmp/inspect_realsense.sh"

# Create the inspection script
cat << 'EOF' > "$INSPECTION_SCRIPT"
#!/bin/bash

echo "Searching for RealSense camera nodes in /proc/device-tree..."
grep -rl "intel" /proc/device-tree | while read -r node; do
    echo "Found node: $node"
    echo "Node details:"
    hexdump -C "$node"
    echo "------------------------------"
done

echo "Searching for depth and IR channels in /proc/device-tree..."
grep -rlE "depth|ir" /proc/device-tree | while read -r node; do
    echo "Found node: $node"
    echo "Node details:"
    hexdump -C "$node"
    echo "------------------------------"
done
EOF

# Make the script executable locally
chmod +x "$INSPECTION_SCRIPT"

# Copy the inspection script to the target device
scp "$INSPECTION_SCRIPT" "$SSH_USER@$DEVICE_IP:/tmp/" || { echo "Failed to copy script to target device"; exit 1; }

# Execute the inspection script on the target device
ssh "$SSH_USER@$DEVICE_IP" "bash /tmp/$(basename "$INSPECTION_SCRIPT")"

# Clean up the inspection script on the target device
ssh "$SSH_USER@$DEVICE_IP" "rm -f /tmp/$(basename "$INSPECTION_SCRIPT")"

# Remove the local inspection script
rm -f "$INSPECTION_SCRIPT"

echo "Done."

