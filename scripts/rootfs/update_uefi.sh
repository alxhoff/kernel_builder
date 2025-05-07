#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
L4T_DIR="$SCRIPT_DIR/L4T_35_4_1"
TBZ_URL="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/release/jetson_linux_r35.4.1_aarch64.tbz2"
TBZ_FILE="jetson_linux_r35.4.1_aarch64.tbz2"

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
    mkdir "$L4T_DIR"
    tar -xjf "$SCRIPT_DIR/$TBZ_FILE" -C "$L4T_DIR" --strip-components=1

    echo "🧹 Removing archive..."
    rm "$SCRIPT_DIR/$TBZ_FILE"
fi

# --- FLASH UEFI ---
cd "$L4T_DIR"
echo "🚀 Flashing UEFI bootloader only..."
./flash.sh --no-systemimg -c bootloader/t186ref/cfg/flash_t234_qspi.xml jetson-agx-orin-devkit mmcblk0p1

