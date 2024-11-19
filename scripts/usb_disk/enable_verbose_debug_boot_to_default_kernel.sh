#!/bin/bash

set -e

# Function to display help
show_help() {
    echo "Usage: $0 [--help]"
    echo
    echo "This script detects unmounted disk partitions, prompts the user to select the one containing the root filesystem,"
    echo "mounts the selected partition, and modifies the boot/extlinux/extlinux.conf file to enable verbose debugging options."
    echo
    echo "Options:"
    echo "  --help      Show this help message and exit"
    echo
    echo "Requirements:"
    echo "  - Run this script as root or with sudo."
}

# Check for --help option
if [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# Ensure the script is run with sudo
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

# Detect unmounted partitions (exclude disks and include sizes)
echo "Detecting unmounted partitions..."
UNMOUNTED_PARTITIONS=$(lsblk -rno NAME,SIZE,MOUNTPOINT | awk '$3=="" && $1 ~ /[0-9]$/ {print "/dev/" $1, $2}')

if [[ -z "$UNMOUNTED_PARTITIONS" ]]; then
    echo "No unmounted partitions found."
    exit 1
fi

# Display options to the user
echo "Unmounted partitions found:"
PARTITIONS=()
INDEX=1  # Start indexing from 1
while IFS= read -r LINE; do
    PARTITION=$(echo "$LINE" | awk '{print $1}')
    SIZE=$(echo "$LINE" | awk '{print $2}')
    PARTITIONS+=("$PARTITION")
    echo "[$INDEX] $PARTITION (Size: $SIZE)"
    INDEX=$((INDEX + 1))
done <<< "$UNMOUNTED_PARTITIONS"

# Ask the user to select a partition
read -p "Select the partition index for the root filesystem: " SELECTED_INDEX
if ! [[ "$SELECTED_INDEX" =~ ^[0-9]+$ ]] || [ "$SELECTED_INDEX" -lt 1 ] || [ "$SELECTED_INDEX" -gt "${#PARTITIONS[@]}" ]; then
    echo "Invalid selection."
    exit 1
fi

SELECTED_PARTITION="${PARTITIONS[$((SELECTED_INDEX - 1))]}"
echo "Selected partition: $SELECTED_PARTITION"

# Mount the selected partition
MOUNT_POINT="/mnt"
echo "Mounting $SELECTED_PARTITION to $MOUNT_POINT..."
mkdir -p "$MOUNT_POINT"
mount "$SELECTED_PARTITION" "$MOUNT_POINT"

# Modify extlinux.conf
EXTLINUX_CONF="$MOUNT_POINT/boot/extlinux/extlinux.conf"
if [[ ! -f "$EXTLINUX_CONF" ]]; then
    echo "Error: $EXTLINUX_CONF not found on the selected partition."
    umount "$MOUNT_POINT"
    rmdir "$MOUNT_POINT"
    exit 1
fi

echo "Modifying $EXTLINUX_CONF to add verbose debugging options..."
# Add loglevel=7 and earlyprintk if not already present
if grep -q "^[[:space:]]*APPEND" "$EXTLINUX_CONF"; then
    sed -i '/^[[:space:]]*APPEND/ s/$/ loglevel=7 earlyprintk/' "$EXTLINUX_CONF"
else
    echo "No APPEND lines found in $EXTLINUX_CONF. Skipping modification."
fi

echo "Changes made to $EXTLINUX_CONF:"
grep "^[[:space:]]*APPEND" "$EXTLINUX_CONF"

# Unmount the partition
echo "Unmounting $MOUNT_POINT..."
umount "$MOUNT_POINT"

echo "Done. Please reboot the system to apply the changes."

