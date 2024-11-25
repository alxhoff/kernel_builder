#!/bin/bash

# Default values
MODULE="panic_logger.ko"
SSH_USER="root"

function show_help {
    echo "Usage: $0 --device-ip <IP_ADDRESS>"
    echo ""
    echo "Inserts the panic_logger kernel module on the target device."
    echo ""
    echo "Options:"
    echo "  --device-ip <IP_ADDRESS>  IP address of the target device (required)."
    echo "  --help                    Show this help message and exit."
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --device-ip)
            DEVICE_IP="$2"
            shift 2
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

# Check for required arguments
if [[ -z "$DEVICE_IP" ]]; then
    echo "Error: --device-ip is required."
    show_help
    exit 1
fi

# Insert the module
ssh "$SSH_USER@$DEVICE_IP" "modprobe $(basename $MODULE .ko)"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to insert the kernel module '$MODULE' on device $DEVICE_IP."
    exit 1
fi

echo "Kernel module '$MODULE' inserted successfully on device $DEVICE_IP."

