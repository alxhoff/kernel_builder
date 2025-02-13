#!/bin/bash

# Function to show help
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --help      Show this help message"
    echo
    echo "This script applies the necessary Jetson binaries and sets up a default user."
    echo "It runs the following commands:"
    echo "  sudo ./apply_binaries.sh"
    echo "  sudo ./l4t_create_default_user.sh -u cartken -p cartken -n cart1jetson --autologin --accept-license"
    exit 0
}

# Check for --help flag
if [[ "$1" == "--help" ]]; then
    show_help
fi

# Ensure the script is run with sudo
if [[ "$EUID" -ne 0 ]]; then
    echo "Error: This script must be run with sudo."
    exit 1
fi

echo "Applying Jetson binaries..."
sudo mount --bind /dev rootfs/dev
sudo ./apply_binaries.sh
sudo umount rootfs/dev

echo "Creating default user..."
pushd tools
sudo ./l4t_create_default_user.sh -u cartken -p cartken -n cart1jetson --autologin --accept-license
popd

echo "Setup completed successfully!"

