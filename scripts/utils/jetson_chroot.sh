#!/bin/bash

# Script: jetson_chroot.sh
# Description: Script to chroot into a Jetson root filesystem with internet access.
# Author: Linux Specialist

# Function to display help
show_help() {
    cat <<EOF
Usage: $0 [options] <rootfs_directory>

Options:
  --help       Show this help message.
  cleanup      Clean up mount points if the script is accidentally closed.

Description:
  This script sets up a chroot environment for a Jetson root filesystem, ensuring:
    1. Internet access is available within the chroot for installing packages.
    2. Necessary devices and filesystems are mounted in the chroot environment.
    3. A cleanup option to unmount filesystems in case the script exits unexpectedly.

Steps performed by this script:
  1. Bind mount necessary filesystems (e.g., /proc, /sys, /dev, and /dev/pts).
  2. Copy DNS resolver configuration (/etc/resolv.conf) for internet access.
  3. Enter the chroot environment using the "chroot" command.
  4. Cleanup mounted filesystems after exiting the chroot or via the "cleanup" option.

Example:
  To chroot:
    $0 /path/to/jetson/rootfs

  To clean up:
    $0 cleanup /path/to/jetson/rootfs
EOF
}

# Ensure at least one argument is provided
if [ "$#" -lt 1 ]; then
    echo "Error: Missing argument."
    echo "Use --help for usage instructions."
    exit 1
fi

# Check for --help flag
if [ "$1" == "--help" ]; then
    show_help
    exit 0
fi

# Define cleanup function
cleanup() {
    ROOTFS_DIR=$1
    echo "Cleaning up mount points for $ROOTFS_DIR..."

    # Attempt to unmount in reverse order
    umount -l "$ROOTFS_DIR/proc" 2>/dev/null || echo "Warning: /proc not mounted."
    umount -l "$ROOTFS_DIR/sys" 2>/dev/null || echo "Warning: /sys not mounted."
    umount -l "$ROOTFS_DIR/dev/pts" 2>/dev/null || echo "Warning: /dev/pts not mounted."
    umount -l "$ROOTFS_DIR/dev" 2>/dev/null || echo "Warning: /dev not mounted."

    echo "Cleanup completed."
    exit 0
}

# Handle cleanup argument
if [ "$1" == "cleanup" ]; then
    if [ "$#" -ne 2 ]; then
        echo "Error: Missing <rootfs_directory> for cleanup."
        echo "Usage: $0 cleanup <rootfs_directory>"
        exit 1
    fi

    cleanup "$2"
fi

# Root filesystem directory provided as argument
ROOTFS_DIR=$1

# Check if the directory exists
if [ ! -d "$ROOTFS_DIR" ]; then
    echo "Error: Directory $ROOTFS_DIR does not exist."
    exit 1
fi

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

echo "Preparing to chroot into $ROOTFS_DIR..."

# Bind mount necessary filesystems
mount --bind /proc "$ROOTFS_DIR/proc"
mount --bind /sys "$ROOTFS_DIR/sys"
mount --bind /dev "$ROOTFS_DIR/dev"
mount --bind /dev/pts "$ROOTFS_DIR/dev/pts"

# Copy DNS resolver configuration for internet access
cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

# Enter the chroot environment
echo "Entering chroot environment. Type 'exit' to leave."
chroot "$ROOTFS_DIR" /bin/bash

# Cleanup after exiting chroot
cleanup "$ROOTFS_DIR"

