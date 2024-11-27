#!/bin/bash

# Default values
SSH_USER="root"

function show_help {
    echo "Usage: $0 --device-ip <IP_ADDRESS>"
    echo ""
    echo "Triggers a kernel panic on the target device using sysrq."
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

# Enable sysrq on the target device
echo "Enabling sysrq on device $DEVICE_IP..."
ssh "$SSH_USER@$DEVICE_IP" "echo 1 > /proc/sys/kernel/sysrq"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to enable sysrq on the target device."
    exit 1
fi

# Trigger the kernel panic
echo "Triggering kernel panic on device $DEVICE_IP..."
ssh "$SSH_USER@$DEVICE_IP" "echo c > /proc/sysrq-trigger"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to trigger the kernel panic on the target device."
    exit 1
fi

echo "Kernel panic successfully triggered on device $DEVICE_IP."

