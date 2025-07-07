#!/bin/bash

set -e

# Default L4T directory (current directory)
L4T_DIR="."

# Function to show help
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --l4t-dir DIR     Path to Linux_for_Tegra directory (default: current directory)"
    echo "  --help            Show this help message"
    echo
    echo "This script applies the necessary Jetson binaries and sets up a default user."
    echo "It runs:"
    echo "  sudo ./apply_binaries.sh"
    echo "  sudo ./tools/l4t_create_default_user.sh -u cartken -p cartken -n cart1jetson --autologin --accept-license"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --l4t-dir)
            L4T_DIR="$2"
            shift 2
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Ensure the script is run with sudo
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run with sudo."
    exit 1
fi

# Ensure the path exists
if [[ ! -d "$L4T_DIR" ]]; then
    echo "Error: L4T directory '$L4T_DIR' does not exist."
    exit 1
fi

ROOTFS_PATH="$L4T_DIR/rootfs"

if [[ ! -d "$ROOTFS_PATH" ]]; then
    echo "Error: Rootfs directory '$ROOTFS_PATH' does not exist. Cannot hold/unhold packages."
    exit 1
fi

echo "Holding nvidia-l4t-core package to prevent pre-installation script failure..."
sudo chroot "$ROOTFS_PATH" apt-mark hold nvidia-l4t-core || true

echo "Applying Jetson binaries in $L4T_DIR..."
sudo "$L4T_DIR/apply_binaries.sh"

echo "Unholding nvidia-l4t-core package..."
sudo chroot "$ROOTFS_PATH" apt-mark unhold nvidia-l4t-core || true

echo "Creating default user..."
pushd "$L4T_DIR/tools" > /dev/null
sudo ./l4t_create_default_user.sh -u cartken -p cartken -n cart1jetson --autologin --accept-license
popd > /dev/null

echo "Setup completed successfully!"

