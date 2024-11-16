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
            echo "Usage: ./set_default_kernel_usb.sh [OPTIONS]"
            echo
            echo "Options:"
            echo "  --help          Display this help message and exit."
            echo "  --dry-run       Simulate the process without making changes."
            echo "  --interactive   Prompt for confirmation before making changes."
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

# Function to unmount the partition
unmount_partition() {
    echo "Unmounting $MOUNT_POINT..."
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

# Function to extract kernel version from image
extract_kernel_version() {
    local image_path=$1
    strings "$image_path" | grep -E "Linux version [0-9]+\.[0-9]+\.[0-9]+" | head -n 1 | awk '{print $3}'
}

# Function to find kernel components
list_complete_kernels() {
    echo "Scanning for kernel components..."

    # Associative arrays for components
    declare -A kernel_images
    declare -A initrd_files
    declare -A dtb_files
    declare -A modules_dirs
    complete_kernels=()

    # Find kernel images and extract versions
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

    # Find initrd files
    INITRD_FILES=$(find "$MOUNT_POINT/boot" -name "initrd.img-*" 2>/dev/null)
    for INITRD in $INITRD_FILES; do
        INITRD_NAME=$(basename "$INITRD")
        KERNELVERSION="${INITRD_NAME#initrd.img-}"
        initrd_files["$KERNELVERSION"]=$INITRD
    done

    # Find dtb files
    DTB_FILES=$(find "$MOUNT_POINT/boot/dtb" -name "tegra234-p3701-0000-p3737-0000*.dtb" 2>/dev/null)
    for DTB in $DTB_FILES; do
        DTB_NAME=$(basename "$DTB")
        LOCALVERSION="${DTB_NAME#tegra234-p3701-0000-p3737-0000}"
        LOCALVERSION="${LOCALVERSION%.dtb}"
        dtb_files["$LOCALVERSION"]=$DTB
    done

    # Find modules directories
    MODULES_DIRS=$(find "$MOUNT_POINT/lib/modules" -mindepth 1 -maxdepth 1 -type d)
    for MODULE_DIR in $MODULES_DIRS; do
        MODULE_DIR_NAME=$(basename "$MODULE_DIR")
        modules_dirs["$MODULE_DIR_NAME"]=$MODULE_DIR
    done

    # Identify complete kernels
    for KEY in "${!kernel_images[@]}"; do
        IFS=":" read -r KERNELVERSION LOCALVERSION <<< "$KEY"
        MODULES_DIR="${modules_dirs[$KERNELVERSION]}"
        INITRD_FILE="${initrd_files[$KERNELVERSION]}"
        DTB_FILE="${dtb_files[$LOCALVERSION]}"

        if [ -f "$INITRD_FILE" ] && [ -f "$DTB_FILE" ] && [ -d "$MODULES_DIR" ]; then
            complete_kernels+=("$KERNELVERSION|${kernel_images[$KEY]}|$INITRD_FILE|$DTB_FILE")
            echo "Found Complete Kernel:"
            echo "  - Kernel Image: $(basename "${kernel_images[$KEY]}")"
            echo "  - Initrd: $(basename "$INITRD_FILE")"
            echo "  - DTB: $(basename "$DTB_FILE")"
            echo "  - Modules Directory: $MODULES_DIR"
        fi
    done

    if [ ${#complete_kernels[@]} -eq 0 ]; then
        echo "No complete kernels found. Exiting."
        exit 1
    fi
}

# Function to update extlinux.conf
update_extlinux_conf() {
    local kernel_image="$1"
    local initrd="$2"
    local dtb="$3"
    local extlinux_conf="$MOUNT_POINT/boot/extlinux/extlinux.conf"

    if [ ! -f "$extlinux_conf" ]; then
        echo "Error: extlinux.conf not found at $extlinux_conf."
        exit 1
    fi

    echo "Updating extlinux.conf to set the new default kernel..."
    if [ "$DRY_RUN" == true ]; then
        echo "[Dry-run] Would update extlinux.conf with:"
        echo "  - Kernel Image: $kernel_image"
        echo "  - Initrd: $initrd"
        echo "  - DTB: $dtb"
    else
        cp "$extlinux_conf" "$extlinux_conf.bak"
        sed -i.bak \
            -e "s|^\s*LINUX .*|      LINUX /boot/$kernel_image|" \
            -e "s|^\s*INITRD .*|      INITRD /boot/$initrd|" \
            -e "s|^\s*FDT .*|      FDT /boot/dtb/$dtb|" \
            "$extlinux_conf"
        echo "extlinux.conf updated successfully."
    fi
}

# Function to allow user to select a kernel
select_and_set_default_kernel() {
    echo -e "\nSelect the kernel to set as default:"
    local index=1
    for entry in "${complete_kernels[@]}"; do
        IFS="|" read -r KERNELVERSION IMAGE INITRD DTB <<< "$entry"
        echo "$index) Kernel Version: $KERNELVERSION"
        echo "   Image: $(basename "$IMAGE")"
        echo "   Initrd: $(basename "$INITRD")"
        echo "   DTB: $(basename "$DTB")"
        ((index++))
    done

    read -p "Enter the number of the kernel to set as default: " choice
    if [[ "$choice" -ge 1 && "$choice" -le "${#complete_kernels[@]}" ]]; then
        entry="${complete_kernels[$((choice - 1))]}"
        IFS="|" read -r KERNELVERSION IMAGE INITRD DTB <<< "$entry"
        prompt_confirmation "Set Kernel $KERNELVERSION as default?" && update_extlinux_conf "$(basename "$IMAGE")" "$(basename "$INITRD")" "$(basename "$DTB")"
    else
        echo "Invalid selection. Exiting."
        exit 1
    fi
}

# Main script
select_partition
mount_partition
list_complete_kernels
select_and_set_default_kernel
unmount_partition

echo -e "\nDefault kernel configuration updated successfully."
exit 0

