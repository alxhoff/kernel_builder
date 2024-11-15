#!/bin/bash

# Manage boot-time tracing (enable/disable function graph tracing)
# Usage: ./manage_boot_trace.sh [<device-ip>] --enable | --disable

if [[ "$1" == "--help" ]]; then
  cat << EOF
Usage: ./manage_boot_trace.sh [<device-ip>] --enable | --disable

Description:
  This script enables or disables function graph tracing during boot by modifying the kernel boot parameters.

Parameters:
  <device-ip>       IP address of the target device (e.g., Jetson Orin). Optional if 'device_ip' file exists.
  --enable          Enables function graph tracing during boot.
  --disable         Disables function graph tracing during boot.

Workflow:
  1. Reads the device IP from a 'device_ip' file in the script's parent directory, or uses the provided argument.
  2. Connects to the target device over SSH.
  3. Modifies the bootloader configuration file (e.g., /boot/extlinux/extlinux.conf):
     - Adds "ftrace=function_graph" to kernel boot parameters when enabling.
     - Removes "ftrace=function_graph" from kernel boot parameters when disabling.
  4. Prompts the user to reboot the device for changes to take effect.

Examples:
  Enable function graph tracing during boot:
    ./manage_boot_trace.sh 192.168.1.100 --enable

  Enable function graph tracing during boot (device_ip file exists):
    ./manage_boot_trace.sh --enable

  Disable function graph tracing during boot:
    ./manage_boot_trace.sh 192.168.1.100 --disable
EOF
  exit 0
fi

# Get the device IP
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ -z "$1" ] || [[ "$1" == "--"* ]]; then
    echo "Error: <device-ip> is required if 'device_ip' file does not exist."
    echo "Usage: $0 [<device-ip>] --enable | --disable"
    exit 1
  fi
  DEVICE_IP=$1
  shift
fi

ACTION="$1"
BOOT_CONFIG_FILE="/boot/extlinux/extlinux.conf"
USERNAME="root"

if [ -z "$ACTION" ]; then
  echo "Usage: $0 [<device-ip>] --enable | --disable"
  exit 1
fi

if [ "$ACTION" != "--enable" ] && [ "$ACTION" != "--disable" ]; then
  echo "Invalid action: $ACTION. Use --enable or --disable."
  exit 1
fi

modify_boot_config() {
  local ACTION=$1
  if [ "$ACTION" == "--enable" ]; then
    echo "Enabling function graph tracing during boot..."
    ssh "$USERNAME@$DEVICE_IP" "sed -i '/^APPEND /s/$/ ftrace=function_graph/' $BOOT_CONFIG_FILE"
    echo "Function graph tracing enabled for boot."
  elif [ "$ACTION" == "--disable" ]; then
    echo "Disabling function graph tracing during boot..."
    ssh "$USERNAME@$DEVICE_IP" "sed -i '/ftrace=function_graph/d' $BOOT_CONFIG_FILE"
    echo "Function graph tracing disabled for boot."
  fi
}

# Modify the bootloader configuration
modify_boot_config "$ACTION"

echo "Done. Reboot the device for the changes to take effect."

