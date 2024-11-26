#!/bin/bash

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

# Install trace-cmd utility for kernel tracing
if [[ "$1" == "--help" ]]; then
  cat << EOF
Usage: $0

Description:
  Installs the 'trace-cmd' utility on the target device for recording, managing, and analyzing kernel traces.

Examples:
  Install trace-cmd utility on the target:
    $0 --device-ip 192.168.1.100
EOF
  exit 0
fi

echo "Installing trace-cmd on target $DEVICE_IP..."
ssh root@"$DEVICE_IP" "apt update && apt install -y trace-cmd"
echo "Installation completed on target $DEVICE_IP."

