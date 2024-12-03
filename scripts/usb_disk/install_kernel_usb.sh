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

list_complete_kernels() {
    KERNELS_DIR="$(realpath "$(dirname "$0")")/../../kernels"
    INDEX=1

    # Clear arrays
    COMPLETE_KERNELS=()

    # Iterate through each kernel name folder
    for KERNEL in "$KERNELS_DIR"/*; do
        if [ -d "$KERNEL" ]; then
            KERNEL_NAME=$(basename "$KERNEL")
            MODULES_DIR="$KERNEL/modules/lib/modules"
            BOOT_DIR="$KERNEL/modules/boot"

            # Check if the required directories exist
            if [ -d "$MODULES_DIR" ] && [ -d "$BOOT_DIR" ]; then
                # Iterate through each kernel version (directory under modules)
                for MODULE_VERSION_DIR in "$MODULES_DIR"/*; do
                    if [ -d "$MODULE_VERSION_DIR" ]; then
                        FULL_VERSION=$(basename "$MODULE_VERSION_DIR")

                        # Extract the base kernel version and localversion
                        BASE_KERNEL_VERSION=$(echo "$FULL_VERSION" | grep -oP '^[0-9]+\.[0-9]+\.[0-9]+')
                        LOCALVERSION=$(echo "$FULL_VERSION" | sed "s/^${BASE_KERNEL_VERSION}//")

                        # Locate Image dynamically by matching the localversion
                        IMAGE_FILE=$(find "$BOOT_DIR" -type f -name "Image.${LOCALVERSION}" -print -quit)
                        # Locate DTB dynamically by matching the localversion
                        DTB_FILE=$(find "$BOOT_DIR" -type f -name "tegra234-p3701-0000-p3737-0000${LOCALVERSION}.dtb" -print -quit)

                        # Validate all components exist
                        if [ -n "$IMAGE_FILE" ] && [ -n "$DTB_FILE" ] && [ -d "$MODULE_VERSION_DIR" ]; then
                            echo "$INDEX) Kernel: $KERNEL_NAME"
                            echo "   Base Kernel Version: $BASE_KERNEL_VERSION"
                            echo "   Localversion: $LOCALVERSION"
                            echo "   Image: $(basename "$IMAGE_FILE")"
                            echo "   DTB: $(basename "$DTB_FILE")"
                            echo "   Modules: $FULL_VERSION"
                            COMPLETE_KERNELS+=("$KERNEL_NAME|$BASE_KERNEL_VERSION|$LOCALVERSION|$IMAGE_FILE|$DTB_FILE|$MODULE_VERSION_DIR")
                            ((INDEX++))
                        fi
                    fi
                done
            fi
        fi
    done

    if [ ${#COMPLETE_KERNELS[@]} -eq 0 ]; then
        echo "No complete kernels found."
        exit 1
    fi
}

# Function to prompt user to select a kernel
select_kernel() {
    list_complete_kernels
    echo -e "\nPlease enter the number corresponding to the kernel configuration you wish to install:"
    read -p "Kernel Number: " KERNEL_INDEX
    if ! [[ "$KERNEL_INDEX" =~ ^[0-9]+$ ]] || [ "$KERNEL_INDEX" -lt 1 ] || [ "$KERNEL_INDEX" -gt ${#COMPLETE_KERNELS[@]} ]; then
        echo "Invalid selection. Exiting."
        exit 1
    fi

    # Parse the selected kernel configuration
    IFS='|' read -r KERNEL_NAME BASE_KERNEL_VERSION LOCALVERSION IMAGE_PATH DTB_PATH MODULES_PATH <<< "${COMPLETE_KERNELS[$KERNEL_INDEX-1]}"

    echo "Selected configuration:"
    echo "  Kernel: $KERNEL_NAME"
    echo "  Base Kernel Version: $BASE_KERNEL_VERSION"
    echo "  Localversion: $LOCALVERSION"
    echo "  Image: $(basename "$IMAGE_PATH")"
    echo "  DTB: $(basename "$DTB_PATH")"
    echo "  Modules: $MODULES_PATH"

    # Assign global variables for use in other functions
    SELECTED_KERNEL_NAME="$KERNEL_NAME"
    SELECTED_BASE_KERNEL_VERSION="$BASE_KERNEL_VERSION"
    SELECTED_LOCALVERSION="$LOCALVERSION"
    SELECTED_IMAGE_PATH="$IMAGE_PATH"
    SELECTED_DTB_PATH="$DTB_PATH"
    SELECTED_MODULES_PATH="$MODULES_PATH"
}

# Function to copy kernel files to USB boot drive
copy_kernel_files() {
    echo "Copying kernel files to USB boot drive..."

    if [ "$DRY_RUN" == true ]; then
        echo "[Dry-run] Would copy kernel Image, DTB, and modules to USB boot drive."
    else
        # Copy Image file
        echo "Copying Image file..."
        if [ -f "$SELECTED_IMAGE_PATH" ]; then
            echo "  - Copying $(basename "$SELECTED_IMAGE_PATH")"
            cp "$SELECTED_IMAGE_PATH" "$MOUNT_POINT/boot/"
        else
            echo "Error: Image file $(basename "$SELECTED_IMAGE_PATH") not found."
        fi

        # Copy DTB file
        echo "Copying DTB file..."
        if [ -f "$SELECTED_DTB_PATH" ]; then
            echo "  - Copying $(basename "$SELECTED_DTB_PATH")"
            cp "$SELECTED_DTB_PATH" "$MOUNT_POINT/boot/dtb/"
        else
            echo "Error: DTB file $(basename "$SELECTED_DTB_PATH") not found."
        fi

        # Copy module files
        echo "Copying module files..."
        if [ -d "$SELECTED_MODULES_PATH" ]; then
            MODULE_VERSION=$(basename "$SELECTED_MODULES_PATH")
            TARGET_MODULE_DIR="$MOUNT_POINT/lib/modules/$MODULE_VERSION"
            mkdir -p "$TARGET_MODULE_DIR"

            find "$SELECTED_MODULES_PATH" -type f | while read -r FILE; do
                RELATIVE_PATH=${FILE#$SELECTED_MODULES_PATH/}
                DEST_PATH="$TARGET_MODULE_DIR/$RELATIVE_PATH"
                DEST_DIR=$(dirname "$DEST_PATH")
                mkdir -p "$DEST_DIR"
                cp "$FILE" "$DEST_PATH"
                echo "  - Copied $(basename "$FILE") to $DEST_PATH"
            done
        else
            echo "Error: Modules directory $(basename "$SELECTED_MODULES_PATH") not found."
        fi
    fi
}

# Function to regenerate initrd file
regenerate_initrd() {
    # Ensure KERNEL_VERSION is set
    KERNEL_VERSION=$(basename "$SELECTED_MODULES_PATH")

    if [ -z "$KERNEL_VERSION" ]; then
        echo "Error: KERNEL_VERSION is not set. Cannot regenerate initrd."
        exit 1
    fi

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
        mkdir -p "$MOUNT_POINT/etc"

        # Bind the host resolv.conf into the chroot environment
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

