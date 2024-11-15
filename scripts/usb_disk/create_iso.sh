#!/bin/bash

# Create "imgs" folder if it doesn't exist
SCRIPT_DIR=$(dirname "$(realpath "$0")")
IMG_DIR="$SCRIPT_DIR/imgs"
mkdir -p "$IMG_DIR"

# Function to display help
function show_help() {
    echo "Usage: $0 [--dry-run | --safe | --no-compression | --help]"
    echo
    echo "This script creates an image of an unmounted USB disk."
    echo
    echo "Options:"
    echo "  --dry-run         Simulate the creation process without making any changes."
    echo "  --safe            Clone the entire disk, including unused space, for exact replication."
    echo "  --no-compression  Skip compression when creating the image."
    echo "  --help            Display this help message."
    echo
    echo "Examples:"
    echo "  Create an efficient image:  $0"
    echo "  Clone the entire disk:       $0 --safe"
    echo "  Skip compression:            $0 --no-compression"
    echo "  Simulate the process:        $0 --dry-run"
    exit 0
}

# Check for options
DRY_RUN=false
SAFE_MODE=false
NO_COMPRESSION=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            echo "Dry-run mode enabled. No changes will be made."
            ;;
        --safe)
            SAFE_MODE=true
            echo "Safe mode enabled. The entire disk will be cloned."
            ;;
        --no-compression)
            NO_COMPRESSION=true
            echo "No compression mode enabled. Raw image will be saved."
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
    shift
done

# List unmounted disks
echo "Available unmounted disks:"
DISKS=($(lsblk -dnpo NAME | while read -r disk; do
    if [ -z "$(lsblk -nro MOUNTPOINT "$disk" | grep -v "^$")" ]; then
        echo "$disk"
    fi
done))

if [ ${#DISKS[@]} -eq 0 ]; then
    echo "No unmounted disks available."
    exit 1
fi

for i in "${!DISKS[@]}"; do
    SIZE=$(lsblk -dnro SIZE "${DISKS[$i]}")
    PARTITIONS=$(lsblk -no NAME,SIZE,MOUNTPOINT "${DISKS[$i]}" | tail -n +2)
    echo "$((i + 1)): ${DISKS[$i]} ($SIZE)"
    echo "$PARTITIONS"
done

# Prompt user to select a disk by index
read -p "Enter the number of the disk to create an image from: " DISK_INDEX
DISK_INDEX=$((DISK_INDEX - 1))

if [ -z "${DISKS[$DISK_INDEX]}" ]; then
    echo "Invalid selection."
    exit 1
fi

DEVICE="${DISKS[$DISK_INDEX]}"
echo "Selected disk: $DEVICE"

# Ask user for image filename
read -p "Enter a filename for the image (without extension): " FILENAME
EXT=".img"
[ "$NO_COMPRESSION" = false ] && EXT=".img.gz"
FILENAME="$IMG_DIR/$FILENAME$EXT"

RAW_IMG="${FILENAME%.gz}"

if $DRY_RUN; then
    if $SAFE_MODE; then
        echo "Dry-run: Would execute the following commands:"
        echo "  sudo dd if=$DEVICE of=$RAW_IMG bs=4M status=progress"
    else
        USED_SECTORS=$(sudo blockdev --getsize64 "$DEVICE")
        echo "Dry-run: Would execute the following commands:"
        echo "  sudo dd if=$DEVICE of=$RAW_IMG bs=512 count=$((USED_SECTORS / 512)) status=progress"
    fi

    if [ "$NO_COMPRESSION" = false ]; then
        echo "  gzip $RAW_IMG"
    fi
    exit 0
fi

if $SAFE_MODE; then
    # Clone the entire disk
    echo "Cloning the entire disk..."
    sudo dd if="$DEVICE" of="$RAW_IMG" bs=4M status=progress
else
    # Efficient mode: Clone only used sectors
    USED_SECTORS=$(sudo blockdev --getsize64 "$DEVICE")
    echo "Creating an efficient image..."
    sudo dd if="$DEVICE" of="$RAW_IMG" bs=512 count=$((USED_SECTORS / 512)) status=progress
fi

if [ "$NO_COMPRESSION" = false ]; then
    echo "Compressing the image..."
    gzip "$RAW_IMG"
fi

echo "Image created and saved as $FILENAME."

