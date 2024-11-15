#!/bin/bash

# Script to list kernel versions on a target Jetson device and set a selected version as default
# Usage: ./set_default_kernel_jetson.sh [--help] [--dry-run]
#
# Arguments:
#   --help       Show this help message and exit.
#   --dry-run    Optional argument to simulate the changes without updating extlinux.conf.
#
# Description:
# This script connects to a Jetson device via SSH, lists all kernel versions that share the same localversion string
# (i.e., Image, initrd, modules folder, and DTB files), and allows the user to set one of these versions as the default
# in the extlinux.conf file.

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

# Parse script arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: ./set_default_jetson_kernel.sh [--help] [--dry-run]"
            echo
            echo "Arguments:"
            echo "  --help       Show this help message and exit."
            echo "  --dry-run    Optional argument to simulate the changes without updating extlinux.conf."
            echo
            echo "Description:"
            echo "  This script connects to a Jetson device via SSH, lists all kernel versions that share the same localversion string"
            echo "  (i.e., Image, initrd, modules folder, and DTB files), and allows the user to set one of these versions as the default"
            echo "  in the extlinux.conf file."
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
    shift
done

echo "Connecting to Jetson device at $DEVICE_IP to list kernel versions..."

# Fetch kernel images, initrd files, and DTB files that share the same localversion
IMAGE_FILES=$(ssh root@$DEVICE_IP "ls /boot/Image*" 2>/dev/null)
INITRD_FILES=$(ssh root@$DEVICE_IP "ls /boot/initrd.img-*" 2>/dev/null)
DTB_FILES=$(ssh root@$DEVICE_IP "ls /boot/dtb/tegra234-p3701-0000-p3737-0000*.dtb" 2>/dev/null)
MODULES_DIRS=$(ssh root@$DEVICE_IP "ls -d /lib/modules/5.10.120*" 2>/dev/null)

# Map to store versions with complete sets
declare -A KERNEL_VERSIONS

# Populate the map with versions that have all components
for IMAGE in $IMAGE_FILES; do
    if [[ $IMAGE =~ Image\.(.*) ]]; then
        LOCALVERSION="${BASH_REMATCH[1]}"
        INITRD="/boot/initrd.img-${LOCALVERSION}"
        DTB="/boot/dtb/tegra234-p3701-0000-p3737-0000${LOCALVERSION}.dtb"
        MODULES="/lib/modules/5.10.120${LOCALVERSION}"

        if ssh root@$DEVICE_IP "[ -f $INITRD ] && [ -f $DTB ] && [ -d $MODULES ]"; then
            KERNEL_VERSIONS[$LOCALVERSION]="Image: $IMAGE, Initrd: $INITRD, DTB: $DTB, Modules: $MODULES"
        fi
    fi
done

# Check if we have any valid kernel versions
if [ ${#KERNEL_VERSIONS[@]} -eq 0 ]; then
    echo "No complete kernel versions found on the device."
    exit 1
fi

# Display the available kernel versions
echo "Available kernel versions with all components:"
index=1
for VERSION in "${!KERNEL_VERSIONS[@]}"; do
    echo "  [$index] Version: $VERSION"
    echo "      ${KERNEL_VERSIONS[$VERSION]}"
    ((index++))
done

# Prompt the user to select a version to set as default
read -p "Enter the number of the kernel version to set as default: " SELECTED_INDEX

# Validate the selected index
if ! [[ "$SELECTED_INDEX" =~ ^[0-9]+$ ]] || [ "$SELECTED_INDEX" -lt 1 ] || [ "$SELECTED_INDEX" -gt ${#KERNEL_VERSIONS[@]} ]; then
    echo "Invalid selection. Exiting."
    exit 1
fi

# Get the selected version
SELECTED_VERSION=""
index=1
for VERSION in "${!KERNEL_VERSIONS[@]}"; do
    if [ "$index" -eq "$SELECTED_INDEX" ]; then
        SELECTED_VERSION="$VERSION"
        break
    fi
    ((index++))
done

# Extract components for the selected version
SELECTED_IMAGE="/boot/Image.${SELECTED_VERSION}"
SELECTED_INITRD="/boot/initrd.img-${SELECTED_VERSION}"
SELECTED_DTB="/boot/dtb/tegra234-p3701-0000-p3737-0000${SELECTED_VERSION}.dtb"

# Update extlinux.conf to set the selected kernel as default
EXTLINUX_CONF_PATH="/boot/extlinux/extlinux.conf"
UPDATE_COMMAND="sed -i.bak '
  s|^\s*LINUX .*|      LINUX ${SELECTED_IMAGE}|;
  s|^\s*INITRD .*|      INITRD ${SELECTED_INITRD}|;
  s|^\s*FDT .*|      FDT ${SELECTED_DTB}|;
' $EXTLINUX_CONF_PATH"

echo "Updating extlinux.conf to set the selected kernel as default..."
if [ "$DRY_RUN" == true ]; then
    echo "[Dry-run] Would run: ssh root@$DEVICE_IP \"$UPDATE_COMMAND\""
else
    ssh root@$DEVICE_IP "$UPDATE_COMMAND"
    echo "Default kernel updated successfully to version: $SELECTED_VERSION"
fi

exit 0

