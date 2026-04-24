#!/bin/bash

set -e

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo."
  exit 1
fi

# File and URL definitions
ROOTFS_PKG="Tegra_Linux_Sample-Root-Filesystem_r36.4.3_aarch64.tbz2"
JETSON_LINUX_PKG="Jetson_Linux_r36.4.3_aarch64.tbz2"

ROOTFS_URL="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/release/Tegra_Linux_Sample-Root-Filesystem_r36.4.3_aarch64.tbz2"
JETSON_LINUX_URL="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/release/Jetson_Linux_r36.4.3_aarch64.tbz2"

# Download Tegra Root Filesystem if it doesn't exist
if [ ! -f "$ROOTFS_PKG" ]; then
    echo "Downloading Tegra Root Filesystem..."
    wget "$ROOTFS_URL" -O "$ROOTFS_PKG"
else
    echo "Tegra Root Filesystem package already exists, skipping download."
fi

# Download Jetson Linux package if it doesn't exist
if [ ! -f "$JETSON_LINUX_PKG" ]; then
    echo "Downloading Jetson Linux package..."
    wget "$JETSON_LINUX_URL" -O "$JETSON_LINUX_PKG"
else
    echo "Jetson Linux package already exists, skipping download."
fi

# Extract packages if Linux_for_Tegra directory doesn't exist
if [ ! -d "Linux_for_Tegra" ]; then
    echo "Extracting Jetson Linux package..."
    if [ -n "$SUDO_USER" ]; then
        sudo -u "$SUDO_USER" tar -xjf "$JETSON_LINUX_PKG"
    else
        tar -xjf "$JETSON_LINUX_PKG"
    fi

    echo "Extracting Tegra Root Filesystem..."
    tar -xjf "$ROOTFS_PKG" -C Linux_for_Tegra/rootfs
else
    echo "Linux_for_Tegra directory already exists, skipping extractions."
fi

cd Linux_for_Tegra

echo "Applying binaries..."
./apply_binaries.sh

pushd tools
echo "Creating default user..."
./l4t_create_default_user.sh -u cartken -p cartken -n testjetson --autologin --accept-license
popd

echo "Flashing the device..."
./flash.sh jetson-agx-orin-devkit mmcblk0p1

echo "Done."

