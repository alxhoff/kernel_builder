#!/bin/bash

# Script to list kernel versions on a target Jetson device and set a selected version as default
# Usage: ./set_default_kernel_jetson.sh [--help] [--dry-run]
#
# Arguments:
#   --help       Show this help message and exit.
#   --dry-run    Optional argument to simulate the changes without updating extlinux.conf.
#
# Description:
# This script connects to a Jetson device via SSH, lists all kernel versions and their components
# (Image, Initrd, DTB files, and Modules folder). It allows the user to set one of these versions
# as the default in the extlinux.conf file, while also identifying orphaned components.

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
            echo "Usage: ./set_default_kernel_jetson.sh [--help] [--dry-run]"
            echo
            echo "Arguments:"
            echo "  --help       Show this help message and exit."
            echo "  --dry-run    Optional argument to simulate the changes without updating extlinux.conf."
            echo
            echo "Description:"
            echo "  This script connects to a Jetson device via SSH, lists all kernel versions and their components"
            echo "  (Image, initrd, DTB files, and Modules folder), and allows the user to set one as the default"
            echo "  in the extlinux.conf file. Orphaned components are also displayed."
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

# Fetch kernel images, initrd files, DTB files, and modules directories
IMAGE_FILES=$(ssh root@$DEVICE_IP "ls /boot/Image*" 2>/dev/null)
INITRD_FILES=$(ssh root@$DEVICE_IP "ls /boot/initrd.img-*" 2>/dev/null)
DTB_FILES=$(ssh root@$DEVICE_IP "ls /boot/dtb/tegra234-p3701-0000-p3737-0000*.dtb" 2>/dev/null)
MODULES_DIRS=$(ssh root@$DEVICE_IP "ls -d /lib/modules/5.10.120*" 2>/dev/null)

# Map to store versions with complete sets and orphaned components
declare -A KERNEL_VERSIONS
ORPHANED_COMPONENTS=()

echo -e "\n--- Listing All Kernel Components ---"

# Populate the map with versions that have all components
for IMAGE in $IMAGE_FILES; do
    if [[ $IMAGE =~ Image\.(.*) ]]; then
        LOCALVERSION="${BASH_REMATCH[1]}"
        KERNEL_VERSION="5.10.120${LOCALVERSION}"
        INITRD="/boot/initrd.img-${KERNEL_VERSION}"
        DTB="/boot/dtb/tegra234-p3701-0000-p3737-0000${LOCALVERSION}.dtb"
        MODULES="/lib/modules/${KERNEL_VERSION}"

        # Check if all components exist
        if ssh root@$DEVICE_IP "[ -f $INITRD ] && [ -f $DTB ] && [ -d $MODULES ]"; then
            KERNEL_VERSIONS[$LOCALVERSION]="\n    Image: $IMAGE\n    Initrd: $INITRD\n    DTB: $DTB\n    Modules: $MODULES"
        fi
    fi
done

# Display the available complete kernel versions before moving on to incomplete sets
echo -e "\n--- Available Complete Kernel Versions ---"
if [ ${#KERNEL_VERSIONS[@]} -eq 0 ]; then
    echo "No complete kernel versions found on the device."
    exit 1
fi

index=1
for VERSION in "${!KERNEL_VERSIONS[@]}"; do
    echo -e "  [$index] Version: $VERSION"
    echo -e "      ${KERNEL_VERSIONS[$VERSION]}"
    ((index++))
done

# Now, display incomplete sets
for IMAGE in $IMAGE_FILES; do
    if [[ $IMAGE =~ Image\.(.*) ]]; then
        LOCALVERSION="${BASH_REMATCH[1]}"
        KERNEL_VERSION="5.10.120${LOCALVERSION}"
        INITRD="/boot/initrd.img-${KERNEL_VERSION}"
        DTB="/boot/dtb/tegra234-p3701-0000-p3737-0000${LOCALVERSION}.dtb"
        MODULES="/lib/modules/${KERNEL_VERSION}"

        # Check for incomplete sets
        if ! ssh root@$DEVICE_IP "[ -f $INITRD ] && [ -f $DTB ] && [ -d $MODULES ]"; then
            echo -e "\nIncomplete set for version: $LOCALVERSION"
            echo "  Image: $IMAGE"
            ssh root@$DEVICE_IP "[ -f $INITRD ]" && echo "  Initrd: $INITRD" || { echo "  Initrd: MISSING"; ORPHANED_COMPONENTS+=("$INITRD"); }
            ssh root@$DEVICE_IP "[ -f $DTB ]" && echo "  DTB: $DTB" || { echo "  DTB: MISSING"; ORPHANED_COMPONENTS+=("$DTB"); }
            ssh root@$DEVICE_IP "[ -d $MODULES ]" && echo "  Modules: $MODULES" || { echo "  Modules: MISSING"; ORPHANED_COMPONENTS+=("$MODULES"); }
        fi
    else
        echo -e "\nOrphan Image found: $IMAGE"
        ORPHANED_COMPONENTS+=("$IMAGE")
    fi
done

# Display orphaned Initrds
for INITRD in $INITRD_FILES; do
    if [[ $INITRD =~ initrd\.img\-(.*) ]]; then
        LOCALVERSION="${BASH_REMATCH[1]#5.10.120}"
        if [ -z "${KERNEL_VERSIONS[$LOCALVERSION]}" ]; then
            echo -e "\nOrphan Initrd found: $INITRD"
            ORPHANED_COMPONENTS+=("$INITRD")
        fi
    fi
done

# Display orphaned DTBs
for DTB in $DTB_FILES; do
    if [[ $DTB =~ tegra234-p3701-0000-p3737-0000(.*)\.dtb ]]; then
        LOCALVERSION="${BASH_REMATCH[1]}"
        if [ -z "${KERNEL_VERSIONS[$LOCALVERSION]}" ]; then
            echo -e "\nOrphan DTB found: $DTB"
            ORPHANED_COMPONENTS+=("$DTB")
        fi
    fi
done

# Display orphaned Modules directories
for MODULES in $MODULES_DIRS; do
    if [[ $MODULES =~ 5\.10\.120(.*) ]]; then
        LOCALVERSION="${BASH_REMATCH[1]}"
        if [ -z "${KERNEL_VERSIONS[$LOCALVERSION]}" ]; then
            echo -e "\nOrphan Modules directory found: $MODULES"
            ORPHANED_COMPONENTS+=("$MODULES")
        fi
    fi
done

# Prompt the user to delete orphaned components after listing complete kernels
if [ ${#ORPHANED_COMPONENTS[@]} -gt 0 ]; then
    echo -e "\n--- Orphaned Components Found ---"
    for COMPONENT in "${ORPHANED_COMPONENTS[@]}"; do
        echo "  $COMPONENT"
    done

    read -p "Do you want to delete all orphaned components? (default: no) [y/N]: " DELETE_ORPHANS
    if [[ "$DELETE_ORPHANS" =~ ^[yY]$ ]]; then
        for COMPONENT in "${ORPHANED_COMPONENTS[@]}"; do
            if [ "$DRY_RUN" == true ]; then
                echo "[Dry-run] Would delete: $COMPONENT"
            else
                echo "Deleting: $COMPONENT"
                ssh root@$DEVICE_IP "rm -rf $COMPONENT"
            fi
        done
        echo "Orphaned components deleted."
    else
        echo "Orphaned components were not deleted."
    fi
fi

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
SELECTED_INITRD="/boot/initrd.img-5.10.120${SELECTED_VERSION}"
SELECTED_DTB="/boot/dtb/tegra234-p3701-0000-p3737-0000${SELECTED_VERSION}.dtb"

# Update extlinux.conf to set the selected kernel as default
EXTLINUX_CONF_PATH="/boot/extlinux/extlinux.conf"
UPDATE_COMMAND="sed -i.bak '
  s|^\s*LINUX .*|      LINUX ${SELECTED_IMAGE}|;
  s|^\s*INITRD .*|      INITRD ${SELECTED_INITRD}|;
  s|^\s*FDT .*|      FDT ${SELECTED_DTB}|;
' $EXTLINUX_CONF_PATH"

echo -e "\nUpdating extlinux.conf to set the selected kernel as default..."
if [ "$DRY_RUN" == true ]; then
    echo "[Dry-run] Would run: ssh root@$DEVICE_IP \"$UPDATE_COMMAND\""
else
    ssh root@$DEVICE_IP "$UPDATE_COMMAND"
    echo "Default kernel updated successfully to version: $SELECTED_VERSION"
fi

exit 0

