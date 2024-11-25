#!/bin/bash

# Variables
FIRMWARE_DIR="/xavier_ssd/rs_firmware"
DEVICE_PREFIX="/dev/d4xx-dfu-30-001" # Ensure it points to the /dev path
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

# Default mode: Sequential
MULTITHREADED=false

# Get the device IP
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip" | tr -d '\r')
else
  if [ "$#" -lt 1 ]; then
    echo "Usage: $0 [--multithreaded] [--help] [<device-ip>]"
    exit 1
  fi
  DEVICE_IP=$1
fi

# SSH function to execute commands remotely
run_ssh() {
    local COMMAND="$1"
    ssh -t root@"$DEVICE_IP" "$COMMAND"
}

# Show available firmware binaries and prompt user to select one
select_firmware() {
    echo "Available firmware binaries on target device:"
    mapfile -t BINARY_LIST < <(run_ssh "ls -1 $FIRMWARE_DIR 2>/dev/null" | tr -d '\r')
    if [ ${#BINARY_LIST[@]} -eq 0 ]; then
        echo "Error: No binaries found in $FIRMWARE_DIR on target device."
        exit 1
    fi

    for i in "${!BINARY_LIST[@]}"; do
        echo "[$i] ${BINARY_LIST[$i]}"
    done

    echo
    read -p "Enter the index of the binary you want to use: " INDEX
    if [[ ! "$INDEX" =~ ^[0-9]+$ ]] || [ "$INDEX" -lt 0 ] || [ "$INDEX" -ge "${#BINARY_LIST[@]}" ]]; then
        echo "Invalid selection. Exiting."
        exit 1
    fi

    SELECTED_BINARY="${BINARY_LIST[$INDEX]}"
    echo "You selected: $SELECTED_BINARY"
}

# Reload the kernel module for d4xx devices
reload_d4xx_module() {
    echo "Reloading d4xx kernel module..."
    if run_ssh "rmmod d4xx && modprobe d4xx"; then
        echo "Kernel module reloaded successfully."
    else
        echo "Error: Failed to reload d4xx kernel module. Exiting."
        exit 1
    fi
}

# Function to update a single device
update_device() {
    local DEVICE="$1"
    local BINARY="$2"

    echo "Updating device $DEVICE with binary $BINARY..."
    local COMMAND="cat $FIRMWARE_DIR/$BINARY > $DEVICE"
    echo "[Running command on target]: $COMMAND"
    if ! run_ssh "$COMMAND"; then
        echo "Error: Initial attempt to update device $DEVICE failed."
        reload_d4xx_module
        echo "Retrying update for device $DEVICE..."
        if ! run_ssh "$COMMAND"; then
            echo "Error: Failed to update device $DEVICE after reloading kernel module."
            return 1
        fi
    fi
    echo "Successfully updated device $DEVICE."
}

# Update devices sequentially
update_devices_sequential() {
    for DEVICE_SUFFIX in a b c d; do
        DEVICE="$DEVICE_PREFIX$DEVICE_SUFFIX"
        if run_ssh "[ -e $DEVICE ]"; then
            update_device "$DEVICE" "$SELECTED_BINARY"
        else
            echo "Device $DEVICE not found. Skipping."
        fi
    done
}

# Update devices in parallel
update_devices_parallel() {
    for DEVICE_SUFFIX in a b c d; do
        DEVICE="$DEVICE_PREFIX$DEVICE_SUFFIX"
        if run_ssh "[ -e $DEVICE ]"; then
            update_device "$DEVICE" "$SELECTED_BINARY" &
        else
            echo "Device $DEVICE not found. Skipping."
        fi
    done

    # Wait for all background tasks to complete
    wait
}

# Show help message
show_help() {
    cat <<EOF
Usage: $0 [--multithreaded] [--help] [<device-ip>]

Options:
  --multithreaded  Update devices in parallel. Default is sequential.
  --help           Show this help message.
  <device-ip>      Specify the target device's IP address. If not provided,
                   the script will attempt to read the IP from device_ip.

Description:
  This script updates up to four DFU devices (a, b, c, d) with a firmware
  binary chosen by the user from the directory $FIRMWARE_DIR on the target
  device. If a device update fails initially, the script will unload and
  reload the d4xx kernel module and retry. By default, devices are updated
  sequentially. Use the --multithreaded option to update devices in parallel.
EOF
}

# Main script
while [[ "$1" == --* ]]; do
    case "$1" in
        --multithreaded)
            MULTITHREADED=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Select firmware
select_firmware

# Perform the update
if $MULTITHREADED; then
    echo "Updating devices in multithreaded mode..."
    update_devices_parallel
else
    echo "Updating devices sequentially..."
    update_devices_sequential
fi

