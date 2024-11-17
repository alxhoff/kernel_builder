#!/bin/bash

# Ensure the script is run with appropriate permissions
if [[ $EUID -ne 0 ]]; then
    echo "Please run this script as root or with sudo."
    exit 1
fi

# Variables
KERNELS_DIR="$(realpath "$(dirname "$0")/../../kernels")"
MOUNT_POINT="/mnt"
SSH_USER="root"
DEVICE_IP_FILE="$(realpath "$(dirname "$0")/../device_ip")"
TARGET_MODE="jetson"  # Default mode, can be "jetson" or "usb"
DRY_RUN=false
STEP_BY_STEP=false

JETSON_DEFAULT_KERNEL_SCRIPT="$(realpath "$(dirname "$0")/../util_jetson/set_default_kernel_jetson.sh")"
USB_DEFAULT_KERNEL_SCRIPT="$(realpath "$(dirname "$0")/../usb_disk/set_default_kernel.sh")"

# Functions
show_help() {
    echo "Usage: ./manage_kernels.sh [OPTIONS]"
    echo
    echo "Options:"
    echo "  --help          Show this help message and exit."
    echo "  --dry-run       Simulate the actions without making changes."
    echo "  --usb           Deploy to a USB rootfs instead of the Jetson device."
    echo "  --step-by-step  Prompt for confirmation at each step."
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help) show_help ;;
            --dry-run) DRY_RUN=true ;;
            --usb) TARGET_MODE="usb" ;;
            --step-by-step) STEP_BY_STEP=true ;;
            *) echo "Unknown argument: $1"; exit 1 ;;
        esac
        shift
    done
}

step_prompt() {
    local STEP_DESCRIPTION="$1"
    if [[ $STEP_BY_STEP == true ]]; then
        echo -e "\n[Step-by-Step] $STEP_DESCRIPTION"
        read -p "Proceed? [Y/n]: " CONFIRM
        case "$CONFIRM" in
            [nN]) return 1 ;;
        esac
    fi
    return 0
}

list_kernels() {
    echo "Available kernels:"
    local index=1
    for KERNEL in "$KERNELS_DIR"/*; do
        if [[ -d "$KERNEL" ]]; then
            echo "[$index] $(basename "$KERNEL")"
            KERNELS_LIST+=("$KERNEL")
            ((index++))
        fi
    done
}

select_kernel() {
    list_kernels
    echo -e "\nSelect a kernel:"
    read -p "Kernel number: " KERNEL_INDEX
    if ! [[ "$KERNEL_INDEX" =~ ^[0-9]+$ ]] || [[ "$KERNEL_INDEX" -lt 1 ]] || [[ "$KERNEL_INDEX" -gt "${#KERNELS_LIST[@]}" ]]; then
        echo "Invalid selection."
        exit 1
    fi
    SELECTED_KERNEL="${KERNELS_LIST[$KERNEL_INDEX-1]}"
    echo "Selected kernel: $(basename "$SELECTED_KERNEL")"
}

deploy_to_jetson() {
    if [[ ! -f $DEVICE_IP_FILE ]]; then
        echo "Device IP file not found: $DEVICE_IP_FILE"
        exit 1
    fi
    local DEVICE_IP
    DEVICE_IP=$(<"$DEVICE_IP_FILE")
    echo "Deploying kernel to Jetson device at $DEVICE_IP..."

    step_prompt "Sync modules and kernel image to the Jetson" || return

    # Sync modules
    rsync -avz --progress "$SELECTED_KERNEL/modules/lib/modules/" "$SSH_USER@$DEVICE_IP:/lib/modules/"

    # Sync Images
    for IMAGE_FILE in "$SELECTED_KERNEL/modules/boot/Image"*; do
        if [[ -f $IMAGE_FILE ]]; then
            echo "Syncing $(basename "$IMAGE_FILE") to Jetson..."
            rsync -avz --progress "$IMAGE_FILE" "$SSH_USER@$DEVICE_IP:/boot/"
        fi
    done

    # Sync DTBs
    for DTB_FILE in "$SELECTED_KERNEL/modules/boot/tegra234-"*.dtb; do
        if [[ -f $DTB_FILE ]]; then
            echo "Syncing $(basename "$DTB_FILE") to Jetson..."
            rsync -avz --progress "$DTB_FILE" "$SSH_USER@$DEVICE_IP:/boot/dtb/"
        fi
    done

    echo "Kernel files deployed to Jetson."

    KERNEL_VERSION=$(basename "$(ls -d "$SELECTED_KERNEL/modules/lib/modules/"* 2>/dev/null | head -n 1)")
    if [[ -z $KERNEL_VERSION ]]; then
        echo "Error: Unable to determine kernel version from $SELECTED_KERNEL."
        exit 1
    fi

    read -p "Do you want to regenerate initrd on the Jetson? (default: no) [y/N]: " REGENERATE_INITRD
    if [[ "$REGENERATE_INITRD" =~ ^[yY]$ ]]; then
        regenerate_initrd "jetson"
    else
        echo "Initrd regeneration skipped on the Jetson."
    fi

    read -p "Do you want to change the default kernel? (default: no) [y/N]: " CHANGE_DEFAULT
    if [[ "$CHANGE_DEFAULT" =~ ^[yY]$ ]]; then
        echo "Changing the default kernel on the Jetson..."
        $JETSON_DEFAULT_KERNEL_SCRIPT
    else
        echo "Default kernel update skipped."
    fi
}

deploy_to_usb() {
    echo "Listing available unmounted USB partitions..."
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -v '/'

    read -p "Enter the partition to use (e.g., sdb1): /dev/" PARTITION_NAME
    PARTITION_PATH="/dev/$PARTITION_NAME"
    if [[ ! -b $PARTITION_PATH ]]; then
        echo "Invalid partition."
        exit 1
    fi

    step_prompt "Mount the USB partition" || return
    mount "$PARTITION_PATH" "$MOUNT_POINT"
    echo "Mounted $PARTITION_PATH at $MOUNT_POINT."

    step_prompt "Sync modules and kernel image to the USB rootfs" || return

    rsync -avz --progress "$SELECTED_KERNEL/modules/lib/modules/" "$MOUNT_POINT/lib/modules/"

    for IMAGE_FILE in "$SELECTED_KERNEL/modules/boot/Image"*; do
        if [[ -f $IMAGE_FILE ]]; then
            echo "Syncing $(basename "$IMAGE_FILE")..."
            rsync -avz --progress "$IMAGE_FILE" "$MOUNT_POINT/boot/"
        fi
    done

    for DTB_FILE in "$SELECTED_KERNEL/modules/boot/tegra234-"*.dtb; do
        if [[ -f $DTB_FILE ]]; then
            echo "Syncing $(basename "$DTB_FILE")..."
            rsync -avz --progress "$DTB_FILE" "$MOUNT_POINT/boot/dtb/"
        fi
    done

    KERNEL_VERSION=$(basename "$(ls -d "$SELECTED_KERNEL/modules/lib/modules/"* 2>/dev/null | head -n 1)")
    if [[ -z $KERNEL_VERSION ]]; then
        echo "Error: Unable to determine kernel version from $SELECTED_KERNEL."
        exit 1
    fi

    echo "Kernel files deployed to $MOUNT_POINT."

    read -p "Do you want to regenerate initrd on the USB rootfs? (default: no) [y/N]: " REGENERATE_INITRD
    if [[ "$REGENERATE_INITRD" =~ ^[yY]$ ]]; then
        regenerate_initrd "usb"
    else
        echo "Initrd regeneration skipped on the USB rootfs."
    fi

    read -p "Do you want to change the default kernel? (default: no) [y/N]: " CHANGE_DEFAULT
    if [[ "$CHANGE_DEFAULT" =~ ^[yY]$ ]]; then
        echo "Changing the default kernel on the USB..."
        $USB_DEFAULT_KERNEL_SCRIPT "$PARTITION_PATH"
    else
        echo "Default kernel update skipped."
    fi

    step_prompt "Unmount the USB partition" || return
    umount "$MOUNT_POINT"
    echo "Unmounted $MOUNT_POINT."
}

# Function to regenerate initrd file
regenerate_initrd() {
    local TARGET="$1"  # "jetson" or "usb"

    if [ "$TARGET" == "usb" ]; then
        echo "Chrooting into USB rootfs and regenerating initrd for kernel version: $KERNEL_VERSION..."
        if [ "$DRY_RUN" == true ]; then
            echo "[Dry-run] Would chroot into USB rootfs and regenerate initrd."
        else
            # Bind the required directories for the chroot environment
            echo "Setting up chroot environment..."
            mount --bind /dev "$MOUNT_POINT/dev"
            mount --bind /proc "$MOUNT_POINT/proc"
            mount --bind /sys "$MOUNT_POINT/sys"
            mount --bind /run "$MOUNT_POINT/run"

            # Write a temporary resolv.conf to enable internet access inside chroot
            echo "nameserver 8.8.8.8" > "$MOUNT_POINT/etc/resolv.conf"

            # Regenerate initrd inside the chroot
            chroot "$MOUNT_POINT" /bin/bash -c "export PATH=/usr/sbin:/usr/bin:/sbin:/bin && apt-get update && apt-get install -y initramfs-tools && update-initramfs -c -k $KERNEL_VERSION"

            # Clean up chroot environment
            rm "$MOUNT_POINT/etc/resolv.conf"
            umount "$MOUNT_POINT/dev"
            umount "$MOUNT_POINT/proc"
            umount "$MOUNT_POINT/sys"
            umount "$MOUNT_POINT/run"

            echo "Initrd regenerated inside USB rootfs."
        fi

    elif [ "$TARGET" == "jetson" ]; then
        echo "Regenerating initrd on the Jetson for kernel version: $KERNEL_VERSION..."
        if [ "$DRY_RUN" == true ]; then
            echo "[Dry-run] Would SSH to the Jetson and regenerate initrd."
        else
            ssh root@$DEVICE_IP "update-initramfs -c -k $KERNEL_VERSION"
            echo "Initrd regenerated on the Jetson."
        fi
    else
        echo "Invalid target specified for initrd regeneration."
        exit 1
    fi
}

main() {
    parse_args "$@"

    step_prompt "Select a kernel" && select_kernel

    if [[ $TARGET_MODE == "jetson" ]]; then
        deploy_to_jetson
    elif [[ $TARGET_MODE == "usb" ]]; then
        deploy_to_usb
    else
        echo "Invalid target mode: $TARGET_MODE"
        exit 1
    fi
}

main "$@"

