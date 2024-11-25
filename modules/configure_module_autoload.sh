#!/bin/bash

# Default values
MODULE_NAME=""
CONFIG_FILE="/etc/modules-load.d"
SSH_USER="root"

function show_help {
    echo "Usage: $0 --device-ip <IP_ADDRESS> --module-name <MODULE_NAME>"
    echo ""
    echo "Configures a kernel module to be loaded at boot on the target device."
    echo ""
    echo "Options:"
    echo "  --device-ip <IP_ADDRESS>  IP address of the target device (required)."
    echo "  --module-name <MODULE_NAME> Name of the kernel module (required)."
    echo "  --help                    Show this help message and exit."
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --device-ip)
            DEVICE_IP="$2"
            shift 2
            ;;
        --module-name)
            MODULE_NAME="$2"
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
if [[ -z "$DEVICE_IP" || -z "$MODULE_NAME" ]]; then
    echo "Error: --device-ip and --module-name are required."
    show_help
    exit 1
fi

# Define the configuration file name
CONFIG_FILE="$CONFIG_FILE/$MODULE_NAME.conf"

# Create the configuration file on the target device
echo "Configuring module '$MODULE_NAME' to load at boot on device $DEVICE_IP..."
ssh "$SSH_USER@$DEVICE_IP" "echo '$MODULE_NAME' | sudo tee $CONFIG_FILE > /dev/null"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to create the configuration file on the target device."
    exit 1
fi

# Verify the configuration
ssh "$SSH_USER@$DEVICE_IP" "cat $CONFIG_FILE"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to verify the configuration on the target device."
    exit 1
fi

echo "Kernel module '$MODULE_NAME' configured to load at boot on device $DEVICE_IP."
echo "Reboot the device to apply changes."

