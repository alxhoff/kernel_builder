#!/bin/bash

# Script to clean up kernel module folders, kernel images, and initrd files on a target Jetson device.
# Usage: ./cleanup_jetson_kernel.sh [--help] [--dry-run] [--interactive]
#
# Arguments:
#   --help          Show this help message and exit.
#   --dry-run       Optional argument to simulate the cleanup without deleting anything.
#   --interactive   Optional argument to prompt for confirmation before each deletion.
#
# Description:
# This script connects to a Jetson device via SSH and performs cleanup of old kernel images,
# module folders, and initrd files. It is useful when multiple kernels have been deployed,
# and you need to remove older versions to free up space and keep the system organized.
# By default, the current kernel (as determined from extlinux.conf) is preserved, and only
# non-default kernel files are removed.
#
# Example Usage:
# 1. To perform a cleanup without deleting anything:
#    ./cleanup_jetson_kernel.sh --dry-run
#
# 2. To perform a cleanup and prompt for confirmation before deleting each file:
#    ./cleanup_jetson_kernel.sh --interactive
#
# 3. To execute a full cleanup without any prompts or simulations:
#    ./cleanup_jetson_kernel.sh

# Set up base paths and read device IP
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
DEVICE_IP_FILE="$SCRIPT_DIR/../device_ip"

if [ ! -f "$DEVICE_IP_FILE" ]; then
    echo "Error: Device IP file not found at $DEVICE_IP_FILE"
    exit 1
fi

DEVICE_IP=$(<"$DEVICE_IP_FILE")

# Default values for script arguments
DRY_RUN=false
INTERACTIVE=false

# Parse script arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: ./cleanup_jetson_kernel.sh [--help] [--dry-run] [--interactive]"
            echo
            echo "Arguments:"
            echo "  --help          Show this help message and exit."
            echo "  --dry-run       Optional argument to simulate the cleanup without deleting anything."
            echo "  --interactive   Optional argument to prompt for confirmation before each deletion."
            echo
            echo "Description:"
            echo "  This script connects to a Jetson device via SSH and performs cleanup of old kernel images,"
            echo "  module folders, and initrd files. It preserves the current kernel as per extlinux.conf"
            echo "  and removes only non-default kernel files."
            echo
            echo "Example Usage:"
            echo "  1. To perform a cleanup without deleting anything:"
            echo "     ./cleanup_jetson_kernel.sh --dry-run"
            echo
            echo "  2. To perform a cleanup and prompt for confirmation before deleting each file:"
            echo "     ./cleanup_jetson_kernel.sh --interactive"
            echo
            echo "  3. To execute a full cleanup without any prompts or simulations:"
            echo "     ./cleanup_jetson_kernel.sh"
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --interactive)
            INTERACTIVE=true
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
    shift
done

echo "Starting cleanup on Jetson device at $DEVICE_IP..."

# Fetch default kernel, initrd, and FDT values from extlinux.conf
EXTLINUX_CONF_PATH="/boot/extlinux/extlinux.conf"

DEFAULT_KERNEL=$(ssh root@$DEVICE_IP "grep -i '^\s*LINUX' $EXTLINUX_CONF_PATH | awk '{print \$2}'")
DEFAULT_INITRD=$(ssh root@$DEVICE_IP "grep -i '^\s*INITRD' $EXTLINUX_CONF_PATH | awk '{print \$2}'")

if [ -z "$DEFAULT_KERNEL" ]; then
    echo "Error: Could not determine default kernel from $EXTLINUX_CONF_PATH."
    exit 1
fi

if [ -z "$DEFAULT_INITRD" ]; then
    echo "Warning: Could not determine default initrd from $EXTLINUX_CONF_PATH. Assuming /boot/initrd as default."
    DEFAULT_INITRD="/boot/initrd" # Assuming default initrd location if not explicitly found
fi

# Extract the localversion from the default kernel image
DEFAULT_LOCALVERSION=""
if [[ $DEFAULT_KERNEL =~ Image\.(.*) ]]; then
    DEFAULT_LOCALVERSION="${BASH_REMATCH[1]}"
else
    DEFAULT_LOCALVERSION="default"
fi

# Function to execute a command on the target device
execute_remote() {
    local cmd=$1
    if [ "$DRY_RUN" == true ]; then
        echo "[Dry-run] Would run: ssh root@$DEVICE_IP \"$cmd\""
    else
        ssh root@$DEVICE_IP "$cmd"
    fi
}

# Iterate over kernel images in /boot on the target device
IMAGE_FILES=$(ssh root@$DEVICE_IP "ls /boot/Image*" 2>/dev/null)
for IMAGE in $IMAGE_FILES; do
    IMAGE_NAME=$(basename "$IMAGE")
    LOCALVERSION=""

    if [[ $IMAGE_NAME =~ Image\.(.*) ]]; then
        LOCALVERSION="${BASH_REMATCH[1]}"
    else
        LOCALVERSION="default"
    fi

    # Determine matching kernel version directory and initrd file
    KERNEL_MODULES_DIR="/lib/modules/5.10.120${LOCALVERSION}"
    INITRD_FILE="/boot/initrd.img-${LOCALVERSION}"

    # Handle cases where the initrd might just be "/boot/initrd"
    if [ "$INITRD_FILE" == "$DEFAULT_INITRD" ] || [ "$DEFAULT_INITRD" == "/boot/initrd" ]; then
        INITRD_FILE="$DEFAULT_INITRD"
    fi

    # Skip the default kernel and its related files
    if [ "$LOCALVERSION" == "$DEFAULT_LOCALVERSION" ]; then
        echo "Skipping default kernel image, modules, and initrd: $IMAGE_NAME, $KERNEL_MODULES_DIR, $INITRD_FILE"
        continue
    fi

    # Interactive prompt to confirm deletion
    REMOVE=true
    if [ "$INTERACTIVE" == true ]; then
        echo -e "\nKernel Image: $IMAGE_NAME"
        echo "Matching Kernel Modules Directory: $KERNEL_MODULES_DIR"
        echo "Matching Initrd File: $INITRD_FILE"
        read -p "Delete kernel image, modules directory, and initrd? (default yes) [Y/n]: " CONFIRM
        case "$CONFIRM" in
            [nN][oO]|[nN]) REMOVE=false ;;
            *) REMOVE=true ;; # Default to yes
        esac
    fi

    # Delete kernel image, modules directory, and initrd if confirmed
    if [ "$REMOVE" == true ]; then
        echo "Deleting kernel image: $IMAGE_NAME"
        execute_remote "rm -f $IMAGE"

        if ssh root@$DEVICE_IP "[ -d $KERNEL_MODULES_DIR ]"; then
            echo "Deleting kernel modules directory: $KERNEL_MODULES_DIR"
            execute_remote "rm -rf $KERNEL_MODULES_DIR"
        fi

        if ssh root@$DEVICE_IP "[ -f $INITRD_FILE ]"; then
            echo "Deleting initrd file: $INITRD_FILE"
            execute_remote "rm -f $INITRD_FILE"
        fi
    else
        echo "Skipped kernel image, modules directory, and initrd: $IMAGE_NAME, $KERNEL_MODULES_DIR, $INITRD_FILE"
    fi
done

echo -e "\nKernel cleanup on Jetson device complete."

