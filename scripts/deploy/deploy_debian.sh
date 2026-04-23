#!/bin/bash

# General script to create a Debian package from a compiled kernel.
# Usage: ./deploy_debian.sh [KERNEL_NAME] [OPTIONS]

set -ex

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_DEPLOYER_PATH="$SCRIPT_DIR/../kernel_deployer.py"

# Ensure kernel name is provided
if [ -z "$1" ]; then
  echo "Error: Kernel name must be provided as the first argument."
  echo "Usage: ./deploy_debian.sh [KERNEL_NAME] [OPTIONS]"
  echo "Use --help for more information."
  exit 1
fi

KERNEL_NAME="$1"
shift # Shift arguments to parse the rest of the options

# Default values
LOCALVERSION_ARG=""
DRY_RUN=false
DTB_NAME_ARG="--dtb-name tegra234-p3701-0000-p3737-0000.dtb"

# Function to display help message
function display_help() {
    echo "Usage: ./deploy_debian.sh [KERNEL_NAME] [OPTIONS]"
    echo ""
    echo "Generate a Debian package from a compiled kernel."
    echo ""
    echo "Arguments:"
    echo "  KERNEL_NAME                Specify the name of the kernel to be packaged (e.g., 'jetson')."
    echo ""
    echo "Options:"
    echo "  --localversion <version>   Specify the kernel version (localversion) for packaging."
    echo "  --dry-run                  Simulate the packaging process without generating the package."
	echo "  --dtb-name <name>           Specify the DTB filename (default: tegra234-p3701-0000-p3737-0000.dtb)."
    echo "  --help                     Display this help message."
    echo ""
    echo "Examples:"
    echo "  ./deploy_debian.sh jetson --localversion my_kernel"
    echo "  ./deploy_debian.sh jetson --dry-run"
    exit 0
}

# Check if --help is passed
if [[ "$1" == "--help" ]]; then
    display_help
    exit 0
fi

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --localversion) LOCALVERSION_ARG="--localversion $2"; shift ;;
        --dry-run) DRY_RUN=true ;;
		--dtb-name) DTB_NAME_ARG="--dtb-name $2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Prepare the command to run
DEPLOY_COMMAND="python3 \"$KERNEL_DEPLOYER_PATH\" deploy-debian --kernel-name \"$KERNEL_NAME\" $DTB_NAME_ARG"

if [ -n "$LOCALVERSION_ARG" ]; then
    DEPLOY_COMMAND+=" $LOCALVERSION_ARG"
fi

if [ "$DRY_RUN" = true ]; then
    DEPLOY_COMMAND+=" --dry-run"
fi

# Print the command before executing
echo "Running command: $DEPLOY_COMMAND"

# Execute deployment command
if ! eval $DEPLOY_COMMAND; then
    echo "Failed to create the Debian package for kernel: $KERNEL_NAME"
    exit 1
fi

echo "Debian package successfully created for kernel: $KERNEL_NAME"




