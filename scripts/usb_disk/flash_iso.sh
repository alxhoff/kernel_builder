#!/bin/bash

# Create "imgs" folder if it doesn't exist
SCRIPT_DIR=$(dirname "$(realpath "$0")")
IMG_DIR="$SCRIPT_DIR/imgs"
mkdir -p "$IMG_DIR"

# Function to display help
function show_help() {
    echo "Usage: $0 [--dry-run | --help]"
    echo
    echo "This script flashes a disk image to an unmounted USB disk."
    echo
    echo "Options:"
    echo "  --dry-run   Simulate the flashing process without making any changes."
    echo "  --help      Display this help message."
    echo
    echo "Examples:"
    echo "  Flash an image:  $0"
    echo "  Simulate flashing:  $0 --dry-run"
    exit 0
}

# Check for options
DRY_RUN=false
if [[ "$1" == "--help" ]]; then
    show_help
elif [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "Dry-run mode enabled. No changes will be made."
fi

# List available images
IMAGES=($(ls "$IMG_DIR" | grep -E '\.img(\.gz)?$'))

if [ ${#IMAGES[@]} -eq 0 ]; then
    echo "No images available in $IMG_DIR."
    exit 1
fi

echo "Available images:"
for i in "${!IMAGES[@]}"; do
    echo "$((i + 1)): ${IMAGES[i]}"
done

# Prompt user to select an image by index
read -p "Enter the number of the image to flash: " IMAGE_INDEX
IMAGE_INDEX=$((IMAGE_INDEX - 1))

if [ -z "${IMAGES[$IMAGE_INDEX]}" ]; then
    echo "Invalid selection."
    exit 1
fi

IMAGE="$IMG_DIR/${IMAGES[$IMAGE_INDEX]}"
echo "Selected image: $IMAGE"

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
read -p "Enter the number of the disk to flash the image to: " DISK_INDEX
DISK_INDEX=$((DISK_INDEX - 1))

if [ -z "${DISKS[$DISK_INDEX]}" ]; then
    echo "Invalid selection."
    exit 1
fi

DEVICE="${DISKS[$DISK_INDEX]}"
echo "Selected disk: $DEVICE"

if $DRY_RUN; then
    echo "Dry-run: Would execute the following command:"
    if [[ "$IMAGE" == *.gz ]]; then
        echo "  gunzip -c $IMAGE | sudo dd of=$DEVICE bs=4M status=progress"
    else
        echo "  sudo dd if=$IMAGE of=$DEVICE bs=4M status=progress"
    fi
    exit 0
fi

# Handle compressed or uncompressed image
if [[ "$IMAGE" == *.gz ]]; then
    echo "Decompressing and flashing the image..."
    gunzip -c "$IMAGE" | sudo dd of="$DEVICE" bs=4M status=progress
else
    echo "Flashing the raw image..."
    sudo dd if="$IMAGE" of="$DEVICE" bs=4M status=progress
fi

sync
echo "Flashing complete."

