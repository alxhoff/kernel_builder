#!/bin/bash

# Default values
MODULE="panic_logger.ko"
SSH_USER="root"

function show_help {
    echo "Usage: $0 --device-ip <IP_ADDRESS> [--module <MODULE_PATH>]"
    echo ""
    echo "Deploys a kernel module to a target device via SSH and makes it ready to load."
    echo ""
    echo "Options:"
    echo "  --device-ip <IP_ADDRESS>  IP address of the target device (required)."
    echo "  --module <MODULE_PATH>    Path to the kernel module file (default: './panic_logger.ko')."
    echo "  --help                    Show this help message and exit."
    echo ""
    echo "Example:"
    echo "  $0 --device-ip 192.168.1.100"
    echo "  $0 --device-ip 192.168.1.100 --module ./custom_logger.ko"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --device-ip)
            DEVICE_IP="$2"
            shift 2
            ;;
        --module)
            MODULE="$2"
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

if [[ ! -f "$MODULE" ]]; then
    echo "Error: Kernel module file '$MODULE' not found."
    exit 1
fi

# Get kernel version on the target device
TARGET_KERNEL_VERSION=$(ssh "$SSH_USER@$DEVICE_IP" "uname -r")
if [[ $? -ne 0 || -z "$TARGET_KERNEL_VERSION" ]]; then
    echo "Error: Failed to retrieve kernel version from the target device."
    exit 1
fi

TARGET_DIR="/lib/modules/$TARGET_KERNEL_VERSION/extra"

# Deploy the module
echo "Deploying kernel module '$MODULE' to device $DEVICE_IP..."

# Create the target directory if it doesn't exist
ssh "$SSH_USER@$DEVICE_IP" "mkdir -p $TARGET_DIR"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to create directory $TARGET_DIR on target device."
    exit 1
fi

# Copy the module to the target device
scp "$MODULE" "$SSH_USER@$DEVICE_IP:$TARGET_DIR/"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to copy the module to the target device."
    exit 1
fi

# Update module dependencies
ssh "$SSH_USER@$DEVICE_IP" "depmod -a"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to update module dependencies on the target device."
    exit 1
fi

# Print success message
echo "Kernel module deployed successfully to $TARGET_DIR on device $DEVICE_IP."
echo "You can load the module on the device with the following command:"
echo "  ssh $SSH_USER@$DEVICE_IP 'modprobe $(basename $MODULE .ko)'"

