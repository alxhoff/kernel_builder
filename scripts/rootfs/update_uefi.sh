#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
L4T_DIR="$SCRIPT_DIR/L4T_35_6_1"
TBZ_URL="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.1/release/jetson_linux_r35.6.1_aarch64.tbz2"
TBZ_FILE="jetson_linux_r35.6.1_aarch64.tbz2"

# --- CHECK ROOT ---
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run with sudo or as root."
    exit 1
fi

# --- DOWNLOAD & EXTRACT ---
if [[ -d "$L4T_DIR" ]]; then
    echo "✅ L4T_35_4_1 already exists, skipping download and extraction."
else
    echo "⬇️  Downloading Jetson Linux R35.4.1..."
    wget --content-disposition "$TBZ_URL" -O "$SCRIPT_DIR/$TBZ_FILE"

    echo "📦 Extracting $TBZ_FILE..."
    mkdir -p "$L4T_DIR"
    tar -xjf "$SCRIPT_DIR/$TBZ_FILE" -C "$L4T_DIR"

    echo "🧹 Removing archive..."
    rm "$SCRIPT_DIR/$TBZ_FILE"

    # --- ROOTFS EXTRACTION ---
    SAMPLE_FS_URL="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.1/tegra_linux_sample-root-filesystem_r35.6.1_aarch64.tbz2"
    SAMPLE_FS_FILE="tegra_linux_sample-root-filesystem_r35.6.1_aarch64.tbz2"
    ROOTFS_DIR="$L4T_DIR/Linux_for_Tegra/rootfs"

    echo "⬇️  Downloading sample root filesystem..."
    wget --content-disposition "$SAMPLE_FS_URL" -O "$SCRIPT_DIR/$SAMPLE_FS_FILE"

    echo "📦 Extracting sample rootfs into Linux_for_Tegra/rootfs..."
    mkdir -p "$ROOTFS_DIR"
    tar -xjf "$SCRIPT_DIR/$SAMPLE_FS_FILE" -C "$ROOTFS_DIR"

    echo "🧹 Removing sample rootfs archive..."
    rm "$SCRIPT_DIR/$SAMPLE_FS_FILE"
fi

# --- FLASH UEFI ---
cd "$L4T_DIR/Linux_for_Tegra"
echo "🚀 Flashing UEFI bootloader only..."
./flash.sh --no-systemimg -c bootloader/t186ref/cfg/flash_t234_qspi.xml jetson-agx-orin-devkit mmcblk0p1

