#!/bin/bash

# General script to deploy a compiled kernel to a device.
# Usage: ./deploy_kernel.sh [KERNEL_NAME] [OPTIONS]

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_DEPLOYER_PATH="$SCRIPT_DIR/../kernel_deployer.py"

# Ensure kernel name is provided
if [ -z "$1" ]; then
  echo "Error: Kernel name must be provided as the first argument."
  echo "Usage: ./deploy_kernel.sh [KERNEL_NAME] [OPTIONS]"
  echo "Use --help for more information."
  exit 1
fi

KERNEL_NAME="$1"
shift # Shift arguments to parse the rest of the options

# Default values
USERNAME="cartken"
DEVICE_IP=""
DRY_RUN=false
LOCALVERSION_ARG=""

# Function to display help message
function display_help() {
    echo "Usage: ./deploy_kernel.sh [KERNEL_NAME] [OPTIONS]"
    echo ""
    echo "Deploy a compiled kernel to a target device."
    echo ""
    echo "Arguments:"
    echo "  KERNEL_NAME                Specify the name of the kernel to be deployed (e.g., 'jetson')."
    echo ""
    echo "Options:"
    echo "  --ip <device-ip>           The IP address of the target device (optional if device_ip file is present)."
    echo "  --user <username>          The username to access the device (optional if device_username file is present)."
    echo "  --dry-run                  Simulate the deployment without copying anything to the target device."
    echo "  --localversion <version>   Specify the kernel version (localversion) for deployment."
    echo "  --help                     Display this help message."
    echo ""
    echo "Examples:"
    echo "  ./deploy_kernel.sh jetson --ip 192.168.1.100 --user cartken --localversion my_kernel"
    echo "  ./deploy_kernel.sh jetson --ip 192.168.1.100 --dry-run"
    echo "  ./deploy_kernel.sh jetson --help"
    exit 0
}

# Check if --help is passed
if [[ "$1" == "--help" ]]; then
    display_help
    exit 0
fi

# Check if device_ip file exists in the script directory
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(<"$SCRIPT_DIR/device_ip")
fi

# Check if device_username file exists in the script directory
if [ -f "$SCRIPT_DIR/device_username" ]; then
  USERNAME=$(<"$SCRIPT_DIR/device_username")
fi

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --ip) DEVICE_IP="$2"; shift ;;
        --user) USERNAME="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        --localversion) LOCALVERSION_ARG="--localversion $2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Ensure DEVICE_IP is set
if [ -z "$DEVICE_IP" ]; then
  echo "Error: Device IP address must be provided either via --ip argument or 'device_ip' file."
  exit 1
fi

# Deploy to device
echo "Deploying compiled kernel to the target device at $DEVICE_IP using kernel_deployer.py..."
DEPLOY_COMMAND="python3 \"$KERNEL_DEPLOYER_PATH\" deploy-jetson --kernel-name \"$KERNEL_NAME\" --ip \"$DEVICE_IP\" --user \"$USERNAME\""

if [ -n "$LOCALVERSION_ARG" ]; then
    DEPLOY_COMMAND+=" $LOCALVERSION_ARG"
fi

if [ "$DRY_RUN" = true ]; then
    DEPLOY_COMMAND+=" --dry-run"
fi

# Execute deployment command
if ! eval $DEPLOY_COMMAND; then
    echo "Failed to deploy the compiled kernel to the target device at $DEVICE_IP"
    exit 1
fi

echo "Kernel successfully deployed to the target device at $DEVICE_IP"

