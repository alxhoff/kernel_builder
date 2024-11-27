#!/bin/bash

# Configuration
MODULE="stack_dump_tracer.ko"
DEPLOY_SCRIPT="../deploy_module.sh" # Adjusted path to the deploy script

# Function to show usage
function show_help {
    echo "Usage: $0 --device-ip <IP_ADDRESS>"
    echo ""
    echo "Deploys the stack_dump_tracer kernel module to a target device."
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

# Check if the deploy script exists
if [[ ! -x "$DEPLOY_SCRIPT" ]]; then
    echo "Error: Deploy script '$DEPLOY_SCRIPT' not found or not executable."
    exit 1
fi

# Check if the module file exists
if [[ ! -f "$MODULE" ]]; then
    echo "Error: Kernel module '$MODULE' not found."
    exit 1
fi

# Call the deploy script
echo "Deploying stack_dump_tracer module to device $DEVICE_IP..."
"$DEPLOY_SCRIPT" --device-ip "$DEVICE_IP" --module "$MODULE"

# Check if deployment succeeded
if [[ $? -eq 0 ]]; then
    echo "stack_dump_tracer module deployed successfully to $DEVICE_IP."
else
    echo "Error: Failed to deploy stack_dump_tracer module to $DEVICE_IP."
    exit 1
fi

