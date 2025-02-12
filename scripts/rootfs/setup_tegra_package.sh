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
ACCESS_TOKEN=""
TAG="latest"
SOC="orin"

# Function to show help
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -j, --jetpack VERSION   Specify JetPack version (default: $JETPACK_VERSION)"
	echo "  --access-token TOKEN     Provide the access token (required)"
    echo "  --tag TAG                Specify tag for get_packages.sh (default: $TAG)"
    echo "  --soc SOC                Specify SoC type for jetson_chroot.sh (default: $SOC)"
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
        --access-token)
            ACCESS_TOKEN="$2"
            shift 2
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        --soc)
            SOC="$2"
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

# Ensure access token is provided
if [[ -z "$ACCESS_TOKEN" ]]; then
    echo "Error: --access-token is required."
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

echo "Cloning Jetson Linux toolchain into $TEGRA_DIR/toolchain..."
sudo -u $(logname) git clone --depth=1 git@gitlab.com:cartken/kernel-os/jetson-linux-toolchain "$TEGRA_DIR/toolchain"
echo "Toolchain cloned successfully."

# Download chroot script
chroot_script="$TEGRA_DIR/jetson_chroot.sh"
echo "Checking for chroot script..."
if [ ! -f "$chroot_script" ]; then
    echo "Downloading chroot script..."
    wget -O "$chroot_script" "https://raw.githubusercontent.com/alxhoff/kernel_builder/refs/heads/master/scripts/utils/jetson_chroot.sh"
	chmod +x $chroot_script
    echo "chroot script downloaded successfully."
fi

GIT_ROOTFS_URL="https://api.github.com/repos/alxhoff/kernel_builder/contents/scripts/rootfs"

echo "Fetching list of files in rootfs folder..."
FILES=$(curl -s "$GIT_ROOTFS_URL" | jq -r '.[].download_url')

if [[ -z "$FILES" ]]; then
    echo "Error: Could not retrieve file list from GitHub."
    exit 1
fi

echo "Downloading all rootfs scripts into $TEGRA_DIR..."

for FILE in $FILES; do
    wget -q --show-progress -P "$TEGRA_DIR/" "$FILE"
done
rm $TEGRA_DIR/setup_tegra_package.sh

echo "All rootfs scripts downloaded successfully."

# **Ensure executable permissions for scripts**
echo "Setting execute permissions for scripts..."
chmod +x "$TEGRA_DIR/"*.sh

cd $TEGRA_DIR

echo "Running get_packages.sh with access token and tag: $TAG..."
echo 'export PATH=/usr/local/sbin:/usr/sbin:/sbin:$PATH' | sudo tee rootfs/root/.bashrc > /dev/null
sudo ./setup_rootfs.sh
./get_packages.sh --access-token "$ACCESS_TOKEN" --tag "$TAG"
sudo cp -r packages rootfs/root/
sudo ./build_kernel.sh
echo "Setting up chroot environment for SoC: $SOC..."
sudo ./jetson_chroot.sh rootfs "$SOC" chroot_setup_commands.txt

echo "Setup completed successfully!"
