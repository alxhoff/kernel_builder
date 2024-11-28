#!/bin/bash

# deploy_targeted_modules.sh
# Script to deploy targeted modules to a Jetson device
# Usage: ./deploy_targeted_modules.sh [--kernel-name <kernel-name>] [--user <username>] [--dry-run] [--localversion <version>]
# Arguments:
#   --kernel-name   Required argument to specify the folder name inside the 'kernels' directory
#   --user          Optional argument to specify the username to access the target device (default: root)
#   --dry-run       Optional argument to simulate the deployment process without copying anything to the Jetson device
#   --localversion  Optional argument to set the local version string used during deployment

if [[ "$1" == "--help" ]]; then
  echo "Usage: ./deploy_targeted_modules.sh [OPTIONS]"
  echo ""
  echo "Deploy targeted kernel modules to a Jetson device. The modules to be deployed must be specified in a file called 'target_modules.txt', which should be located in the same directory as this script."
  echo ""
  echo "Options:"
  echo "  --kernel-name <kernel-name> Specify the folder name inside the 'kernels' directory (required)."
  echo "  --user <username>           Specify the username for accessing the target device (default: root)."
  echo "  --dry-run                   Simulate the deployment process without actually transferring files."
  echo "  --localversion <version>    Specify the local version string used during deployment."
  echo "  --help                      Show this help message and exit."
  echo ""
  echo "Examples:"
  echo "  ./deploy_targeted_modules.sh --kernel-name jetson --localversion custom_version"
  echo "  ./deploy_targeted_modules.sh --kernel-name jetson --user cartken --dry-run"
  echo ""
  echo "Note: The list of target modules must be specified in the 'target_modules.txt' file."
  exit 0
fi

SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_DEPLOYER_SCRIPT="$(realpath "$SCRIPT_DIR/../kernel_deployer.py")"

# Set default values
DEVICE_IP=""
USERNAME="root"
DRY_RUN=false
LOCALVERSION_ARG=""
KERNEL_NAME=""

# Get the device IP from file or require it as an argument
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip" | tr -d '\r')
fi

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --ip)
      if [ -n "$2" ]; then
        DEVICE_IP="$2"
        shift 2
      else
        echo "Error: --ip requires a value"
        exit 1
      fi
      ;;
    --kernel-name)
      if [ -n "$2" ]; then
        KERNEL_NAME="$2"
        shift 2
      else
        echo "Error: --kernel-name requires a value"
        exit 1
      fi
      ;;
    --user)
      if [ -n "$2" ]; then
        USERNAME="$2"
        shift 2
      else
        echo "Error: --user requires a value"
        exit 1
      fi
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --localversion)
      if [ -n "$2" ]; then
        LOCALVERSION_ARG="$2"
        shift 2
      else
        echo "Error: --localversion requires a value"
        exit 1
      fi
      ;;
    *)
      echo "Invalid argument: $1"
      exit 1
      ;;
  esac
done

# Validate that DEVICE_IP is set
if [ -z "$DEVICE_IP" ]; then
  echo "Error: No device IP found. Specify --ip or ensure the 'device_ip' file exists in the script directory."
  exit 1
fi

# Validate that KERNEL_NAME is set
if [ -z "$KERNEL_NAME" ]; then
  echo "Error: --kernel-name is required."
  exit 1
fi

# Validate that kernel_deployer.py exists
if [ ! -f "$KERNEL_DEPLOYER_SCRIPT" ]; then
  echo "Error: kernel_deployer.py not found at $KERNEL_DEPLOYER_SCRIPT"
  exit 1
fi

# Deploy the modules using kernel_deployer.py
COMMAND="python3 \"$KERNEL_DEPLOYER_SCRIPT\" deploy-targeted-modules --kernel-name $KERNEL_NAME --ip $DEVICE_IP --user $USERNAME"
[ "$DRY_RUN" == true ] && COMMAND+=" --dry-run"

echo "Running: $COMMAND"
eval $COMMAND

