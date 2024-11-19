#!/bin/bash

# Ensure the script is being run with root permissions
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root."
  exit 1
fi

# Script to install selected kernels onto a USB boot drive for a Jetson device.
# Usage: ./install_kernel_usb.sh [--help] [--dry-run] [--step-by-step]

# Function to display help
show_help() {
    echo "Usage: ./install_kernel_usb.sh [OPTIONS]"
    echo
    echo "Options:"
    echo "  --help          Display this help message and exit."
    echo "  --dry-run       Simulate the installation process without making any changes."
    echo "  --step-by-step  Run the script interactively, allowing the user to confirm each step."
    echo
    echo "Description:"
    echo "  This script helps you install selected kernels onto a USB boot drive for a Jetson device."
    echo "  It guides you through selecting a USB drive, selecting the rootfs partition,"
    echo "  selecting a complete kernel, and copying the required files to the USB drive."
    echo "  Finally, it regenerates the initrd file and updates the extlinux.conf to prepare the USB drive"
    echo "  for booting on the Jetson device."
    echo
    echo "Examples:"
    echo "  ./install_kernel_usb.sh"
    echo "      Perform the installation of the selected kernel onto the USB drive."
    echo
    echo "  ./install_kernel_usb.sh --dry-run"
    echo "      Simulate the installation process without making any changes. Useful for previewing actions."
    echo
    echo "  ./install_kernel_usb.sh --step-by-step"
    echo "      Run each step interactively, prompting the user before continuing or allowing a skip."
    exit 0
}

# Default values
DRY_RUN=false
STEP_BY_STEP=false

# Parse script arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --help)
            show_help
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --step-by-step)
            STEP_BY_STEP=true
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Use --help for more information."
            exit 1
            ;;
    esac
    shift
done

# Function to prompt for step-by-step mode
step_prompt() {
    local STEP_DESCRIPTION="$1"
    if [ "$STEP_BY_STEP" == true ]; then
        echo -e "\n[Step-by-Step] Next Step: $STEP_DESCRIPTION"
        read -p "Proceed with this step? (yes to proceed, no to skip, exit to quit) [Y/n/exit]: " CONFIRM
        case "$CONFIRM" in
            [nN][oO]|[nN])
                echo "Skipping step: $STEP_DESCRIPTION."
                return 1
                ;;
            [eE][xX][iI][tT])
                echo "Exiting script."
                exit 0
                ;;
            *)
                echo "Proceeding with step: $STEP_DESCRIPTION."
                return 0
                ;;
        esac
    fi
    return 0
}

# Function to list available USB devices that are unmounted and show their details
list_unmounted_drives() {
    echo "Listing unmounted USB drives..."
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "disk|part" | grep -v "/"
}

# Function to prompt user to select a rootfs partition
select_partition() {
    list_unmounted_drives
    echo -e "\nPlease enter the partition name (e.g., sdb1) to select the rootfs partition:"
    read -p "Partition: /dev/" PARTITION_NAME
    PARTITION_PATH="/dev/$PARTITION_NAME"

    if [ ! -b "$PARTITION_PATH" ]; then
        echo "Invalid partition. Exiting."
        exit 1
    fi
}

# Function to mount the selected partition
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

# Function to list complete kernels available on the host
list_complete_kernels() {
    echo "Listing complete kernel versions..."
    KERNELS_DIR="$(realpath $(dirname "$0"))/../../kernels"
    COMPLETE_KERNELS=()
    KERNEL_INFO=()
    INDEX=1

    for KERNEL in "$KERNELS_DIR"/*; do
        if [ -d "$KERNEL" ]; then
            MODULES_DIR="$KERNEL/modules/lib/modules"
            BOOT_DIR="$KERNEL/modules/boot"
            KERNEL_NAME=$(basename "$KERNEL")
            if [ -d "$MODULES_DIR" ] && [ -d "$BOOT_DIR" ]; then
                IMAGE=$(ls "$BOOT_DIR"/Image* 2>/dev/null | head -n 1)
                DTB=$(ls "$BOOT_DIR"/tegra234-p3701-0000-p3737-0000*.dtb 2>/dev/null | head -n 1)
                MODULES=$(ls -d "$MODULES_DIR"/* 2>/dev/null | head -n 1)
                if [ -f "$IMAGE" ] && [ -f "$DTB" ] && [ -d "$MODULES" ]; then
                    echo "$INDEX) Kernel: $KERNEL_NAME"
                    echo "   Image: $(basename "$IMAGE")"
                    echo "   DTB: $(basename "$DTB")"
                    echo "   Modules: $(basename "$MODULES")"
                    COMPLETE_KERNELS+=("$KERNEL")
                    KERNEL_INFO+=("$IMAGE|$DTB|$MODULES")
                    ((INDEX++))
                fi
            fi
        fi
    done
}

# Function to prompt user to select a kernel
select_kernel() {
    list_complete_kernels
    echo -e "\nPlease enter the number corresponding to the kernel you wish to install:"
    read -p "Kernel Number: " KERNEL_INDEX
    if ! [[ "$KERNEL_INDEX" =~ ^[0-9]+$ ]] || [ "$KERNEL_INDEX" -lt 1 ] || [ "$KERNEL_INDEX" -gt ${#COMPLETE_KERNELS[@]} ]; then
        echo "Invalid selection. Exiting."
        exit 1
    fi
    SELECTED_KERNEL=${COMPLETE_KERNELS[$KERNEL_INDEX-1]}

    # Extract kernel information directly from the listing step
    IFS='|' read -r SELECTED_IMAGE_PATH SELECTED_DTB_PATH SELECTED_MODULES_PATH <<< "${KERNEL_INFO[$KERNEL_INDEX-1]}"
    KERNEL_VERSION=$(basename "$SELECTED_MODULES_PATH")
}

# Function to copy kernel files to USB boot drive
copy_kernel_files() {
    BOOT_DIR="$SELECTED_KERNEL/modules/boot"
    MODULES_DIR="$SELECTED_KERNEL/modules/lib/modules"
    echo "Copying kernel files to USB boot drive..."

    if [ "$DRY_RUN" == true ]; then
        echo "[Dry-run] Would copy kernel Image, DTB, and modules to USB boot drive."
    else
        echo "Copying Image files..."
        for IMAGE in "$BOOT_DIR"/Image*; do
            echo "  - Copying $(basename "$IMAGE")"
            cp "$IMAGE" "$MOUNT_POINT/boot/"
        done

        echo "Copying DTB files..."
        for DTB in "$BOOT_DIR"/tegra234-p3701-0000-p3737-0000*.dtb; do
            echo "  - Copying $(basename "$DTB")"
            cp "$DTB" "$MOUNT_POINT/boot/dtb/"
        done

        echo "Copying module files (detailed view)..."
        for MODULE_DIR in "$MODULES_DIR"/*; do
            MODULE_NAME=$(basename "$MODULE_DIR")
            echo "Processing module directory: $MODULE_NAME"

            TARGET_DIR="$MOUNT_POINT/lib/modules/$MODULE_NAME"
            mkdir -p "$TARGET_DIR"

            find "$MODULE_DIR" -type f | while read -r FILE; do
                RELATIVE_PATH=${FILE#$MODULE_DIR/}
                DEST_PATH="$TARGET_DIR/$RELATIVE_PATH"
                DEST_DIR=$(dirname "$DEST_PATH")

                echo "  - Copying $(basename "$FILE") to $DEST_PATH"
                mkdir -p "$DEST_DIR"
                cp "$FILE" "$DEST_PATH"
            done
        done
    fi
}

# Function to regenerate initrd file
regenerate_initrd() {
    echo "Chrooting into USB rootfs and regenerating initrd for kernel version: $KERNEL_VERSION..."
    if [ "$DRY_RUN" == true ]; then
        echo "[Dry-run] Would chroot into USB rootfs, perform apt-get update, install tools, and regenerate initrd for kernel version: $KERNEL_VERSION."
    else
        # Bind the required directories for the chroot environment
        echo "Setting up chroot environment..."
        mount --bind /dev "$MOUNT_POINT/dev"
        mount --bind /proc "$MOUNT_POINT/proc"
        mount --bind /sys "$MOUNT_POINT/sys"
        mount --bind /run "$MOUNT_POINT/run"

        # Ensure /etc exists in the chroot environment
        echo "Ensuring /etc directory exists in chroot environment..."
        mkdir -p "$MOUNT_POINT/etc"

        # Bind the host resolv.conf into the chroot environment
        echo "Binding host's resolv.conf into chroot environment..."
        mount --bind /etc/resolv.conf "$MOUNT_POINT/etc/resolv.conf"

        # Set up environment variables and check for update-initramfs
        echo "Checking for update-initramfs inside chroot..."
        chroot "$MOUNT_POINT" /bin/bash -c "export PATH=/usr/sbin:/usr/bin:/sbin:/bin && command -v update-initramfs >/dev/null 2>&1"
        if [ $? -ne 0 ]; then
            echo "update-initramfs not found inside chroot. Installing initramfs-tools..."
            chroot "$MOUNT_POINT" /bin/bash -c "export PATH=/usr/sbin:/usr/bin:/sbin:/bin && apt-get update && apt-get install -y initramfs-tools"
        else
            echo "update-initramfs is available inside chroot. Skipping installation of initramfs-tools."
        fi

        # Regenerate the initrd
        chroot "$MOUNT_POINT" /bin/bash -c "export PATH=/usr/sbin:/usr/bin:/sbin:/bin && update-initramfs -c -k $KERNEL_VERSION"

        # Clean up chroot environment
        umount "$MOUNT_POINT/etc/resolv.conf"
        umount "$MOUNT_POINT/dev"
        umount "$MOUNT_POINT/proc"
        umount "$MOUNT_POINT/sys"
        umount "$MOUNT_POINT/run"
    fi
}

# Function to update extlinux.conf
update_extlinux_conf() {
    echo "Backing up and updating extlinux.conf..."
    if [ "$DRY_RUN" == true ]; then
        echo "[Dry-run] Would backup and update extlinux.conf."
    else
        # Backup extlinux.conf
        cp "$MOUNT_POINT/boot/extlinux/extlinux.conf" "$MOUNT_POINT/boot/extlinux/extlinux.conf.previous"

        # Use the paths derived from the selected kernel components
        SELECTED_IMAGE=$(basename "$SELECTED_IMAGE_PATH")
        SELECTED_DTB=$(basename "$SELECTED_DTB_PATH")
        SELECTED_INITRD="initrd.img-$KERNEL_VERSION"

        # Update extlinux.conf
        sed -i.bak \
        -e "s|^\s*LINUX .*|      LINUX /boot/$SELECTED_IMAGE|" \
        -e "s|^\s*INITRD .*|      INITRD /boot/$SELECTED_INITRD|" \
        -e "s|^\s*FDT .*|      FDT /boot/dtb/$SELECTED_DTB|" \
        "$MOUNT_POINT/boot/extlinux/extlinux.conf"
    fi
}

# Function to unmount the partition
unmount_partition() {
    echo "Unmounting the USB rootfs..."
    if [ "$DRY_RUN" == true ]; then
        echo "[Dry-run] Would unmount $MOUNT_POINT."
    else
        umount "$MOUNT_POINT"
        if [ $? -eq 0 ]; then
            echo "Unmount successful."
        else
            echo "Failed to unmount the partition. Please check manually."
            exit 1
        fi
    fi
}

# Main execution flow
step_prompt "Select USB Partition" && select_partition
step_prompt "Mount Partition" && mount_partition
step_prompt "Select Kernel" && select_kernel
step_prompt "Copy Kernel Files" && copy_kernel_files
step_prompt "Regenerate Initrd File" && regenerate_initrd
step_prompt "Update extlinux.conf" && update_extlinux_conf
step_prompt "Unmount Partition" && unmount_partition

echo -e "\nKernel installation to USB boot drive completed successfully."
exit 0

