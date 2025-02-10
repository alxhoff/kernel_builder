#!/bin/bash

# Script: jetson_chroot.sh
# Description: Script to chroot into a Jetson root filesystem with internet access.
# Author: Linux Specialist

# Function to display help
show_help() {
    cat <<EOF
Usage: $0 [options] <rootfs_directory> <orin|xavier>

Options:
  --help       Show this help message.
  cleanup      Clean up mount points if the script is accidentally closed.

Description:
  This script sets up a chroot environment for a Jetson root filesystem, ensuring:
    1. Internet access is available within the chroot for installing packages.
    2. Necessary devices and filesystems are mounted in the chroot environment.
    3. The SOC type is set based on user input (either "orin" or "xavier").
    4. A cleanup option to unmount filesystems in case the script exits unexpectedly.

Example:
  To chroot into an Orin-based Jetson:
    $0 /path/to/jetson/rootfs orin

  To chroot into a Xavier-based Jetson:
    $0 /path/to/jetson/rootfs xavier

  To clean up:
    $0 cleanup /path/to/jetson/rootfs
EOF
}

# Ensure at least two arguments are provided
if [ "$#" -lt 2 ]; then
    echo "Error: Missing arguments."
    echo "Use --help for usage instructions."
    exit 1
fi

# Check for --help flag
if [ "$1" == "--help" ]; then
    show_help
    exit 0
fi

# Handle cleanup argument
if [ "$1" == "cleanup" ]; then
    if [ "$#" -ne 2 ]; then
        echo "Error: Missing <rootfs_directory> for cleanup."
        echo "Usage: $0 cleanup <rootfs_directory>"
        exit 1
    fi
    cleanup "$2"
fi

# Root filesystem directory
ROOTFS_DIR=$1
SOC_TYPE=$2  # User-provided SOC type

# Validate SOC type
case "$SOC_TYPE" in
    orin) SOC="t234" ;;
    xavier) SOC="t194" ;;
    *)
        echo "Error: Invalid SOC type. Must be 'orin' or 'xavier'."
        exit 1
        ;;
esac

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

echo "Preparing to chroot into $ROOTFS_DIR with SOC type: $SOC_TYPE ($SOC)..."

# Bind mount necessary filesystems
mount --bind /proc "$ROOTFS_DIR/proc"
mount --bind /sys "$ROOTFS_DIR/sys"
mount --bind /dev "$ROOTFS_DIR/dev"
mount --bind /dev/pts "$ROOTFS_DIR/dev/pts"
mount --bind /tmp "$ROOTFS_DIR/tmp"

# Ensure /tmp has correct permissions inside chroot
chmod 1777 "$ROOTFS_DIR/tmp"

# Copy DNS resolver configuration for internet access
cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

# Fix NVIDIA repository URLs inside chroot
if [ -f "$ROOTFS_DIR/etc/apt/sources.list.d/nvidia-l4t-apt-source.list" ]; then
    sed -i "s|<SOC>|$SOC|g" "$ROOTFS_DIR/etc/apt/sources.list.d/nvidia-l4t-apt-source.list"
fi

# Enter the chroot environment
echo "Entering chroot environment. Type 'exit' to leave."
chroot "$ROOTFS_DIR" /bin/bash -c "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; exec /bin/bash"

# Cleanup after exiting chroot
cleanup "$ROOTFS_DIR"

