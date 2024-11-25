#!/bin/bash

# Variables
FIRMWARE_DIR="/xavier_ssd/rs_firmware"
DEVICE_PREFIX_A_B="/dev/d4xx-dfu-30-001" # Prefix for devices a and b
DEVICE_PREFIX_C_D="/dev/d4xx-dfu-31-001" # Prefix for devices c and d
RELEASE_CONTAINER="release"             # Docker container to list firmwares
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

# Default mode: Sequential
MULTITHREADED=false
UPDATE_ALL=false

# Get the device IP
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip" | tr -d '\r')
else
  if [ "$#" -lt 1 ]; then
    echo "Usage: $0 [--list | --all | --multithreaded | --help] [<device-ip>]"
    exit 1
  fi
  DEVICE_IP=$1
fi

# SSH function to execute commands remotely
run_ssh() {
    local COMMAND="$1"
    ssh -t root@"$DEVICE_IP" "$COMMAND"
}

# Check and start the Docker container if needed
ensure_release_container_running() {
    echo "Checking if Docker container '$RELEASE_CONTAINER' is running on target device..."
    if ! run_ssh "docker ps --format '{{.Names}}' | grep -q '^${RELEASE_CONTAINER}\$'"; then
        echo "Docker container '$RELEASE_CONTAINER' is not running. Attempting to start..."
        if ! run_ssh "docker ps -a --format '{{.Names}}' | grep -q '^${RELEASE_CONTAINER}\$'"; then
            echo "Error: Docker container '$RELEASE_CONTAINER' does not exist on the target device."
            exit 1
        fi
        run_ssh "docker start $RELEASE_CONTAINER" || {
            echo "Error: Failed to start Docker container '$RELEASE_CONTAINER'."
            exit 1
        }
    else
        echo "Docker container '$RELEASE_CONTAINER' is already running."
    fi
}

# List current firmware information
list_firmware_info() {
    ensure_release_container_running
    echo "Fetching firmware information using 'rs-fw-update'..."
    run_ssh "docker exec $RELEASE_CONTAINER rs-fw-update" || {
        echo "Error: Failed to fetch firmware information."
        exit 1
    }
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
    if [[ "$INDEX" =~ ^[0-9]+$ && "$INDEX" -ge 0 && "$INDEX" -lt "${#BINARY_LIST[@]}" ]]; then
        SELECTED_BINARY="${BINARY_LIST[$INDEX]}"
        echo "You selected: $SELECTED_BINARY"
    else
        echo "Invalid selection. Exiting."
        exit 1
    fi
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

# Update all devices sequentially
update_devices_all() {
    for DEVICE_SUFFIX in a b c d; do
        if [[ "$DEVICE_SUFFIX" == "a" || "$DEVICE_SUFFIX" == "b" ]]; then
            DEVICE="$DEVICE_PREFIX_A_B$DEVICE_SUFFIX"
        else
            DEVICE="$DEVICE_PREFIX_C_D$DEVICE_SUFFIX"
        fi

        if run_ssh "[ -e $DEVICE ]"; then
            update_device "$DEVICE" "$SELECTED_BINARY"
        else
            echo "Device $DEVICE not found. Skipping."
        fi
    done
}

# Update devices one by one with user confirmation
update_devices_prompt() {
    for DEVICE_SUFFIX in a b c d; do
        if [[ "$DEVICE_SUFFIX" == "a" || "$DEVICE_SUFFIX" == "b" ]]; then
            DEVICE="$DEVICE_PREFIX_A_B$DEVICE_SUFFIX"
        else
            DEVICE="$DEVICE_PREFIX_C_D$DEVICE_SUFFIX"
        fi

        if run_ssh "[ -e $DEVICE ]"; then
            read -p "Do you want to update device $DEVICE? [Y/n]: " RESPONSE
            RESPONSE=${RESPONSE:-Y}
            if [[ "$RESPONSE" =~ ^[Yy]$ ]]; then
                update_device "$DEVICE" "$SELECTED_BINARY"
            else
                echo "Skipping device $DEVICE."
            fi
        else
            echo "Device $DEVICE not found. Skipping."
        fi
    done
}

# Show help message
show_help() {
    cat <<EOF
Usage: $0 [--list | --all | --multithreaded | --help] [<device-ip>]

Options:
  --list          Fetch the current firmware information of attached devices.
  --all           Update all devices sequentially without prompting.
  --multithreaded Update devices in parallel.
  --help          Show this help message.
  <device-ip>     Specify the target device's IP address. If not provided,
                  the script will attempt to read the IP from device_ip.

Description:
  This script updates up to four DFU devices (a, b, c, d) with a firmware
  binary chosen by the user from the directory $FIRMWARE_DIR on the target
  device. Devices a and b use prefix $DEVICE_PREFIX_A_B, while devices c and d
  use prefix $DEVICE_PREFIX_C_D. The --list option retrieves the current
  firmware information from the release Docker container.
EOF
}

# Parse options
while [[ "$1" == --* ]]; do
    case "$1" in
        --list)
            list_firmware_info
            exit 0
            ;;
        --all)
            UPDATE_ALL=true
            shift
            ;;
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
if $UPDATE_ALL; then
    echo "Updating all devices sequentially..."
    update_devices_all
elif $MULTITHREADED; then
    echo "Updating devices in multithreaded mode..."
    update_devices_parallel
else
    echo "Updating devices sequentially with prompts..."
    update_devices_prompt
fi

