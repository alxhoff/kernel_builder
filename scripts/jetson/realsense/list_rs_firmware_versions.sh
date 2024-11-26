#!/bin/bash

# Variables
RELEASE_CONTAINER="release" # Docker container to list firmwares
SCRIPT_DIR="$(realpath "$(dirname "$0")/../..")"

# Get the device IP
if [ -f "$SCRIPT_DIR/device_ip" ]; then
    DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip" | tr -d '\r')
else
    if [ "$#" -lt 1 ]; then
        echo "Usage: $0 [--help] <device-ip>"
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
    if ! run_ssh "docker ps --format '{{.Names}}' | grep -q '^${RELEASE_CONTAINER}\$'"; then
        if ! run_ssh "docker ps -a --format '{{.Names}}' | grep -q '^${RELEASE_CONTAINER}\$'"; then
            echo "Error: Docker container '$RELEASE_CONTAINER' does not exist on the target device."
            exit 1
        fi
        run_ssh "docker start $RELEASE_CONTAINER" || {
            echo "Error: Failed to start Docker container '$RELEASE_CONTAINER'."
            exit 1
        }
    fi
}

# List current firmware information
list_firmware_info() {
    ensure_release_container_running
    echo "Fetching firmware information..."
    run_ssh "docker exec $RELEASE_CONTAINER rs-fw-update" || {
        echo "Error: Failed to fetch firmware information."
        exit 1
    }
}

# Show help message
show_help() {
    cat <<EOF
Usage: $0 [--help] [<device-ip>]

Options:
  --help          Show this help message.
  <device-ip>     Specify the target device's IP address. If not provided,
                  the script will attempt to read the IP from 'device_ip'.

Description:
  This script connects to the target device via SSH and lists the current
  firmware information using the 'rs-fw-update' tool in the 'release' Docker
  container. The device IP can either be passed as an argument or stored
  in a file named 'device_ip' in the script's parent directory.
EOF
}

# Main
if [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

list_firmware_info

