#!/bin/bash

# deploy_targeted_modules.sh
# Script to deploy targeted modules to a Jetson device
# Usage: ./deploy_targeted_modules.sh [--ip <device-ip>] [--user <username>] [--dry-run] [--localversion <version>]
# Arguments:
#   --ip            Required argument to specify the IP address of the target device
#   --user          Optional argument to specify the username to access the target device (default: cartken)
#   --dry-run       Optional argument to simulate the deployment process without copying anything to the Jetson device
#   --localversion  Optional argument to set the local version string used during deployment

if [[ "$1" == "--help" ]]; then
  echo "Usage: ./deploy_targeted_modules.sh [OPTIONS]"
  echo ""
  echo "Deploy targeted kernel modules to a Jetson device. The modules to be deployed must be specified in a file called 'target_modules.txt', which should be located in the same directory as this script."
  echo ""
  echo "Options:"
  echo "  --ip <device-ip>         Specify the IP address of the target Jetson device (required)."
  echo "  --user <username>        Specify the username for accessing the target device (default: cartken)."
  echo "  --dry-run                Simulate the deployment process without actually transferring files."
  echo "  --localversion <version> Specify the local version string used during deployment."
  echo "  --help                   Show this help message and exit."
  echo ""
  echo "Examples:"
  echo "  ./deploy_targeted_modules.sh --ip 192.168.1.100 --localversion cartken_version"
  echo "  ./deploy_targeted_modules.sh --ip 192.168.1.100 --user root --dry-run"
  echo ""
  echo "Note: The list of target modules must be specified in the 'target_modules.txt' file."
  exit 0
fi

SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_DEPLOYER_SCRIPT="$SCRIPT_DIR/kernel_deployer.py"

# Set default values
DEVICE_IP=""
USERNAME="cartken"
DRY_RUN=false
LOCALVERSION_ARG=""

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

# Validate arguments
if [ -z "$DEVICE_IP" ]; then
  echo "Error: --ip is required"
  exit 1
fi

# Deploy the modules using kernel_deployer.py
COMMAND="python3 \"$KERNEL_DEPLOYER_SCRIPT\" deploy-targeted-modules --kernel-name jetson --ip $DEVICE_IP --user $USERNAME"
[ "$DRY_RUN" == true ] && COMMAND+=" --dry-run"
[ -n "$LOCALVERSION_ARG" ] && COMMAND+=" --localversion $LOCALVERSION_ARG"

echo "Running: $COMMAND"
eval $COMMAND

