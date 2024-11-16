#!/bin/bash

# Ensure the script is being run with root permissions
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root."
  exit 1
fi

# Default values for arguments
DRY_RUN=false
INTERACTIVE=false

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: ./cleanup_usb_kernel.sh [OPTIONS]"
            echo
            echo "Options:"
            echo "  --help          Display this help message and exit."
            echo "  --dry-run       Simulate the cleanup process without making changes."
            echo "  --interactive   Prompt for confirmation before deleting each item."
            echo
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
            echo "Use --help for more information."
            exit 1
            ;;
    esac
    shift
done

# Function to prompt for confirmation
prompt_confirmation() {
    if [ "$INTERACTIVE" == true ]; then
        read -p "Proceed with this step? (default yes) [Y/n]: " CONFIRM
        case "$CONFIRM" in
            [nN][oO]|[nN])
                return 1
                ;;
            *)
                return 0
                ;;
        esac
    fi
    return 0
}

# Function to list unmounted drives
list_unmounted_drives() {
    echo "Listing unmounted USB drives..."
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "disk|part" | grep -v "/"
}

# Function to select a partition
select_partition() {
    list_unmounted_drives
    echo -e "\nPlease enter the partition name (e.g., sdb1):"
    read -p "Partition: /dev/" PARTITION_NAME
    PARTITION_PATH="/dev/$PARTITION_NAME"

    if [ ! -b "$PARTITION_PATH" ]; then
        echo "Invalid partition. Exiting."
        exit 1
    fi
}

# Function to mount the partition
mount_partition() {
    MOUNT_POINT="/mnt"
    mkdir -p "$MOUNT_POINT"
    echo "Mounting $PARTITION_PATH to $MOUNT_POINT..."
    if [ "$DRY_RUN" == true ]; then
        echo "[Dry-run] Would mount $PARTITION_PATH to $MOUNT_POINT"
    else
        mount "$PARTITION_PATH" "$MOUNT_POINT"
        if [ $? -ne 0 ]; then
            echo "Failed to mount the partition. Exiting."
            exit 1
        fi
    fi
}

# Function to list kernel components
list_kernels() {
    echo "Scanning for kernel components..."
    KERNEL_IMAGES=$(find "$MOUNT_POINT/boot" -name "Image*" 2>/dev/null)
    for IMAGE in $KERNEL_IMAGES; do
        IMAGE_NAME=$(basename "$IMAGE")
        echo "Kernel Image: $IMAGE_NAME"
    done
}

# Function to delete kernel components
delete_kernel_components() {
    for IMAGE in $KERNEL_IMAGES; do
        IMAGE_NAME=$(basename "$IMAGE")
        echo -e "\nKernel Image: $IMAGE_NAME"

        # Find related components
        LOCALVERSION=$(echo "$IMAGE_NAME" | sed 's/Image\.//')
        MODULES_DIR="$MOUNT_POINT/lib/modules/5.10.120${LOCALVERSION}"
        INITRD_FILE="$MOUNT_POINT/boot/initrd.img-${LOCALVERSION}"
        DTB_FILE="$MOUNT_POINT/boot/dtb/tegra234-p3701-0000-p3737-0000${LOCALVERSION}.dtb"

        echo "Modules Directory: $MODULES_DIR"
        echo "Initrd File: $INITRD_FILE"
        echo "DTB File: $DTB_FILE"

        if [ "$INTERACTIVE" == true ]; then
            read -p "Delete this kernel and its components? (default yes) [Y/n]: " CONFIRM
            if [[ "$CONFIRM" =~ ^[nN]$ ]]; then
                continue
            fi
        fi

        # Delete components
        if [ "$DRY_RUN" == true ]; then
            echo "[Dry-run] Would delete: $IMAGE, $MODULES_DIR, $INITRD_FILE, $DTB_FILE"
        else
            rm -f "$IMAGE" "$INITRD_FILE" "$DTB_FILE"
            [ -d "$MODULES_DIR" ] && rm -rf "$MODULES_DIR"
        fi
    done
}

# Function to unmount the partition
unmount_partition() {
    echo "Unmounting $PARTITION_PATH..."
    if [ "$DRY_RUN" == true ]; then
        echo "[Dry-run] Would unmount $MOUNT_POINT"
    else
        umount "$MOUNT_POINT"
        if [ $? -eq 0 ]; then
            echo "Unmount successful."
        else
            echo "Failed to unmount. Please check manually."
            exit 1
        fi
    fi
}

# Main script
select_partition
mount_partition
list_kernels
delete_kernel_components
unmount_partition

echo -e "\nKernel cleanup on USB device completed."
exit 0

