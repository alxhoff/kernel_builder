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
    local message="$1"
    if [ "$INTERACTIVE" == true ]; then
        read -p "$message (default yes) [Y/n]: " CONFIRM
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

# Function to extract kernel version from image
extract_kernel_version() {
    local image_path=$1
    strings "$image_path" | grep -E "Linux version [0-9]+\.[0-9]+\.[0-9]+" | head -n 1 | awk '{print $3}'
}

# Function to list kernel components and identify orphans
list_and_identify_components() {
    echo "Scanning for kernel components..."

    # Use associative arrays to track components and their usage
    declare -A kernel_images
    declare -A initrd_files
    declare -A dtb_files
    declare -A modules_dirs
    declare -A complete_kernels
    used_components=()

    # Collect kernel images and extract kernel version
    KERNEL_IMAGES=$(find "$MOUNT_POINT/boot" -name "Image*" 2>/dev/null)
    for IMAGE in $KERNEL_IMAGES; do
        IMAGE_NAME=$(basename "$IMAGE")
        LOCALVERSION="${IMAGE_NAME#Image.}"
        if [ "$LOCALVERSION" == "$IMAGE_NAME" ]; then
            LOCALVERSION=""
        fi
        KERNELVERSION=$(extract_kernel_version "$IMAGE")

        if [ -n "$KERNELVERSION" ]; then
            kernel_images["$KERNELVERSION:$LOCALVERSION"]=$IMAGE
            echo "Found Kernel Image: $IMAGE_NAME with Kernel Version: $KERNELVERSION"
        fi
    done

    # Collect initrd files
    INITRD_FILES=$(find "$MOUNT_POINT/boot" -name "initrd.img-*" 2>/dev/null)
    for INITRD in $INITRD_FILES; do
        INITRD_NAME=$(basename "$INITRD")
        KERNELVERSION="${INITRD_NAME#initrd.img-}"
        initrd_files["$KERNELVERSION"]=$INITRD
    done

    # Collect dtb files
    DTB_FILES=$(find "$MOUNT_POINT/boot/dtb" -name "tegra234-p3701-0000-p3737-0000*.dtb" 2>/dev/null)
    for DTB in $DTB_FILES; do
        DTB_NAME=$(basename "$DTB")
        LOCALVERSION="${DTB_NAME#tegra234-p3701-0000-p3737-0000}"
        LOCALVERSION="${LOCALVERSION%.dtb}"
        dtb_files["$LOCALVERSION"]=$DTB
    done

    # Collect modules directories
    MODULES_DIRS=$(find "$MOUNT_POINT/lib/modules" -mindepth 1 -maxdepth 1 -type d)
    for MODULE_DIR in $MODULES_DIRS; do
        MODULE_DIR_NAME=$(basename "$MODULE_DIR")
        modules_dirs["$MODULE_DIR_NAME"]=$MODULE_DIR
    done

    # Identify complete kernels and mark their components as used
    for KEY in "${!kernel_images[@]}"; do
        IFS=":" read -r KERNELVERSION LOCALVERSION <<< "$KEY"

        MODULES_DIR="${modules_dirs[$KERNELVERSION]}"
        INITRD_FILE="${initrd_files[$KERNELVERSION]}"
        DTB_FILE="${dtb_files[$LOCALVERSION]}"

        if [ -f "$INITRD_FILE" ] && [ -f "$DTB_FILE" ] && [ -d "$MODULES_DIR" ]; then
            echo "Complete Kernel Found: $(basename "${kernel_images[$KEY]}")"
            echo "  - Modules Directory: $MODULES_DIR"
            echo "  - Initrd File: $INITRD_FILE"
            echo "  - DTB File: $DTB_FILE"

            complete_kernels["$KERNELVERSION"]="$KERNELVERSION"
            complete_kernels["$LOCALVERSION"]="$LOCALVERSION"

            # Mark these components as used
            used_components+=("${kernel_images[$KEY]}" "$INITRD_FILE" "$DTB_FILE" "$MODULES_DIR")

            prompt_confirmation "Do you want to delete the complete kernel $KERNELVERSION?" && {
                delete_component "${kernel_images[$KEY]}"
                delete_component "$MODULES_DIR"
                delete_component "$INITRD_FILE"
                delete_component "$DTB_FILE"
            }
        else
            echo "Incomplete Kernel Components for Image: $(basename "${kernel_images[$KEY]}")"
            [ -z "$MODULES_DIR" ] && echo "  - Missing Modules Directory: /lib/modules/$KERNELVERSION"
            [ -z "$INITRD_FILE" ] && echo "  - Missing Initrd File: initrd.img-$KERNELVERSION"
            if [ -n "$LOCALVERSION" ] && [ -z "$DTB_FILE" ]; then
                echo "  - Missing DTB File: tegra234-p3701-0000-p3737-0000$LOCALVERSION.dtb"
            fi
        fi
    done

    # Identify orphaned components by excluding used ones
    for KERNELVERSION in "${!initrd_files[@]}"; do
        if [[ ! " ${used_components[@]} " =~ " ${initrd_files[$KERNELVERSION]} " ]]; then
            ORPHAN_INITRD="${initrd_files[$KERNELVERSION]}"
            echo "Orphan Initrd File: $ORPHAN_INITRD"
            prompt_confirmation "Do you want to delete the orphan initrd file $ORPHAN_INITRD?" && delete_component "$ORPHAN_INITRD"
        fi
    done

    for LOCALVERSION in "${!dtb_files[@]}"; do
        if [[ ! " ${used_components[@]} " =~ " ${dtb_files[$LOCALVERSION]} " ]]; then
            ORPHAN_DTB="${dtb_files[$LOCALVERSION]}"
            echo "Orphan DTB File: $ORPHAN_DTB"
            prompt_confirmation "Do you want to delete the orphan DTB file $ORPHAN_DTB?" && delete_component "$ORPHAN_DTB"
        fi
    done

    for MODULE_DIR in "${!modules_dirs[@]}"; do
        if [[ ! " ${used_components[@]} " =~ " ${modules_dirs[$MODULE_DIR]} " ]]; then
            ORPHAN_MODULES="${modules_dirs[$MODULE_DIR]}"
            echo "Orphan Modules Directory: $ORPHAN_MODULES"
            prompt_confirmation "Do you want to delete the orphan modules directory $ORPHAN_MODULES?" && delete_component "$ORPHAN_MODULES"
        fi
    done
}

# Function to delete component
delete_component() {
    COMPONENT=$1
    if [ "$DRY_RUN" == true ]; then
        echo "[Dry-run] Would delete: $COMPONENT"
    else
        rm -rf "$COMPONENT"
        echo "Deleted: $COMPONENT"
    fi
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
list_and_identify_components
unmount_partition

echo -e "\nKernel cleanup on USB device completed."
exit 0

