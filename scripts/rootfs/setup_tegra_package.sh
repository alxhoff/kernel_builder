#!/bin/bash

set -e

# Ensure script is run with sudo only for rootfs extraction
if [[ $EUID -ne 0 ]]; then
    ROOTFS_SUDO="sudo"
else
    ROOTFS_SUDO=""
fi

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

# Define JetPack versions and corresponding L4T versions
declare -A JETPACK_L4T_MAP=(
    [5.1.3]=35.5.0
    [5.1.2]=35.4.1
)

# Define URLs for the sources
declare -A ROOTFS_URLS=(
    [5.1.3]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/release/tegra_linux_sample-root-filesystem_r35.5.0_aarch64.tbz2"
    [5.1.2]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/release/tegra_linux_sample-root-filesystem_r35.4.1_aarch64.tbz2"
)

declare -A KERNEL_URLS=(
    [5.1.3]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/sources/public_sources.tbz2"
    [5.1.2]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/sources/public_sources.tbz2"
)

declare -A DRIVER_URLS=(
    [5.1.3]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/release/jetson_linux_r35.5.0_aarch64.tbz2"
    [5.1.2]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/release/jetson_linux_r35.4.1_aarch64.tbz2"
)

# Default values
JETPACK_VERSION="5.1.3"
DOWNLOAD=true

# Function to show help
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -j, --jetpack VERSION   Specify JetPack version (default: $JETPACK_VERSION)"
    echo "                         Available versions: 5.1.3 (L4T ${JETPACK_L4T_MAP[5.1.3]}), 5.1.2 (L4T ${JETPACK_L4T_MAP[5.1.2]})"
    echo "  --no-download           Use existing .tbz2 files instead of downloading"
    echo "  -h, --help              Show this help message"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -j|--jetpack)
            JETPACK_VERSION="$2"
            shift 2
            ;;
        --no-download)
            DOWNLOAD=false
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Validate JetPack version
if [[ -z "${JETPACK_L4T_MAP[$JETPACK_VERSION]}" ]]; then
    echo "Error: Unsupported JetPack version. Use --help to see available versions."
    exit 1
fi

# Define filenames
ROOTFS_FILE="$(basename "${ROOTFS_URLS[$JETPACK_VERSION]}")"
KERNEL_FILE="$(basename "${KERNEL_URLS[$JETPACK_VERSION]}")"
DRIVER_FILE="$(basename "${DRIVER_URLS[$JETPACK_VERSION]}")"

# Download if necessary
if [ "$DOWNLOAD" = true ]; then
    echo "Downloading required files for JetPack $JETPACK_VERSION (L4T ${JETPACK_L4T_MAP[$JETPACK_VERSION]})..."
    wget -c "${ROOTFS_URLS[$JETPACK_VERSION]}" -O "$ROOTFS_FILE"
    wget -c "${KERNEL_URLS[$JETPACK_VERSION]}" -O "$KERNEL_FILE"
    wget -c "${DRIVER_URLS[$JETPACK_VERSION]}" -O "$DRIVER_FILE"
else
    echo "Skipping download, using local files."
    for FILE in "$ROOTFS_FILE" "$KERNEL_FILE" "$DRIVER_FILE"; do
        if [ ! -f "$FILE" ]; then
            echo "Error: Expected file $FILE not found."
            exit 1
        fi
    done
fi

# Extract driver package
TEGRA_DIR="tegra_$JETPACK_VERSION"
sudo -u $(logname) mkdir -p "$TEGRA_DIR"
echo "Extracting driver package: $DRIVER_FILE into $TEGRA_DIR..."
sudo -u $(logname) tar -xjf "$DRIVER_FILE" -C "$TEGRA_DIR"
echo "Driver package extracted successfully. Moving contents out of Linux_for_Tegra..."
mv "$TEGRA_DIR/Linux_for_Tegra"/* "$TEGRA_DIR"/
rmdir "$TEGRA_DIR/Linux_for_Tegra"
echo "Cleanup complete."

# Extract kernel sources
TMP_DIR=$(sudo -u $(logname) mktemp -d)
echo "Extracting public sources: $KERNEL_FILE into $TMP_DIR..."
sudo -u $(logname) tar -xjf "$KERNEL_FILE" -C "$TMP_DIR"
echo "Extracting kernel sources from $TMP_DIR/kernel_src.tbz2 into $TEGRA_DIR/kernel_src..."
sudo -u $(logname) mkdir -p "$TEGRA_DIR/kernel_src"
sudo -u $(logname) tar -xjf "$TMP_DIR/Linux_for_Tegra/source/public/kernel_src.tbz2" -C "$TEGRA_DIR/kernel_src"
echo "Kernel sources extracted successfully."
rm -rf "$TMP_DIR"

# Extract root filesystem
echo "Extracting root filesystem: $ROOTFS_FILE into $TEGRA_DIR/rootfs..."
mkdir -p "$TEGRA_DIR/rootfs"
sudo tar -xjf "$ROOTFS_FILE" -C "$TEGRA_DIR/rootfs"
echo "Root filesystem extracted successfully."

echo "Setup completed successfully!"

