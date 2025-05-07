#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- DEFAULT TARGET VERSION ---
TARGET_VERSION="5.1.5"

# --- PARSE ARGS ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-version)
            TARGET_VERSION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# --- VERSION URLS ---
declare -A TBZ_URLS=(
    ["5.1.2"]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/release/jetson_linux_r35.4.1_aarch64.tbz2"
    ["5.1.3"]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/release/jetson_linux_r35.5.0_aarch64.tbz2"
    ["5.1.4"]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.0/release/jetson_linux_r35.6.0_aarch64.tbz2"
    ["5.1.5"]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.1/release/jetson_linux_r35.6.1_aarch64.tbz2"
    ["6.0DP"]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v2.0/release/jetson_linux_r36.2.0_aarch64.tbz2"
    ["6.2"]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/release/Jetson_Linux_r36.4.3_aarch64.tbz2"
)
declare -A SAMPLE_FS_URLS=(
    ["5.1.2"]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/release/tegra_linux_sample-root-filesystem_r35.4.1_aarch64.tbz2"
    ["5.1.3"]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/release/tegra_linux_sample-root-filesystem_r35.5.0_aarch64.tbz2"
    ["5.1.4"]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.0/release/tegra_linux_sample-root-filesystem_r35.6.0_aarch64.tbz2"
    ["5.1.5"]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.1/tegra_linux_sample-root-filesystem_r35.6.1_aarch64.tbz2"
    ["6.0DP"]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v2.0/release/tegra_linux_sample-root-filesystem_r36.2.0_aarch64.tbz2"
    ["6.2"]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/release/Tegra_Linux_Sample-Root-Filesystem_r36.4.3_aarch64.tbz2"
)

TBZ_URL="${TBZ_URLS[$TARGET_VERSION]}"
SAMPLE_FS_URL="${SAMPLE_FS_URLS[$TARGET_VERSION]}"

[[ -z "$TBZ_URL" || -z "$SAMPLE_FS_URL" ]] && { echo "Unknown or unsupported version: $TARGET_VERSION"; exit 1; }

TBZ_FILE="$(basename "$TBZ_URL")"
SAMPLE_FS_FILE="$(basename "$SAMPLE_FS_URL")"
L4T_DIR="$SCRIPT_DIR/L4T_${TBZ_FILE%.tbz2}"

# --- CHECK ROOT ---
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run with sudo or as root."
    exit 1
fi

# --- DOWNLOAD & EXTRACT ---
if [[ -d "$L4T_DIR" ]]; then
    echo "✅ $L4T_DIR already exists, skipping download and extraction."
else
    echo "⬇️  Downloading Jetson Linux BSP..."
    wget --content-disposition "$TBZ_URL" -O "$SCRIPT_DIR/$TBZ_FILE"

    echo "📦 Extracting $TBZ_FILE..."
    mkdir -p "$L4T_DIR"
    tar -xjf "$SCRIPT_DIR/$TBZ_FILE" -C "$L4T_DIR"

    echo "🧹 Removing archive..."
    rm "$SCRIPT_DIR/$TBZ_FILE"

    # --- ROOTFS EXTRACTION ---
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

