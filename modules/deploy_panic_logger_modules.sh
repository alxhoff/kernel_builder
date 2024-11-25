#!/bin/bash

# Default module paths
MODULE1="panic_logger.ko"
MODULE2="panic_logger_test.ko"

# Path to deploy_module.sh
DEPLOY_SCRIPT="./deploy_module.sh"

function show_help {
    echo "Usage: $0 --device-ip <IP_ADDRESS>"
    echo ""
    echo "Deploys two kernel modules ('panic_logger.ko' and 'panic_logger_test.ko') to a target device."
    echo ""
    echo "Options:"
    echo "  --device-ip <IP_ADDRESS>  IP address of the target device (required)."
    echo "  --help                    Show this help message and exit."
    echo ""
    echo "Example:"
    echo "  $0 --device-ip 192.168.1.100"
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

# Check if deploy_module.sh exists and is executable
if [[ ! -x "$DEPLOY_SCRIPT" ]]; then
    echo "Error: deploy_module.sh not found or not executable."
    exit 1
fi

# Deploy the first module
echo "Deploying module $MODULE1..."
"$DEPLOY_SCRIPT" --device-ip "$DEVICE_IP" --module "$MODULE1"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to deploy $MODULE1."
    exit 1
fi

# Deploy the second module
echo "Deploying module $MODULE2..."
"$DEPLOY_SCRIPT" --device-ip "$DEVICE_IP" --module "$MODULE2"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to deploy $MODULE2."
    exit 1
fi

# Success message
echo "Both modules deployed successfully to device $DEVICE_IP."

