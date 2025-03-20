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
	[6.0DP]=36.2
	[6.2]=36.4.3
)

# Define URLs for the sources
declare -A ROOTFS_URLS=(
    [5.1.3]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/release/tegra_linux_sample-root-filesystem_r35.5.0_aarch64.tbz2"
    [5.1.2]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/release/tegra_linux_sample-root-filesystem_r35.4.1_aarch64.tbz2"
	[6.0DP]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v2.0/release/tegra_linux_sample-root-filesystem_r36.2.0_aarch64.tbz2"
	[6.2]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/release/Tegra_Linux_Sample-Root-Filesystem_r36.4.3_aarch64.tbz2"
)

declare -A KERNEL_URLS=(
    [5.1.3]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/sources/public_sources.tbz2"
    [5.1.2]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/sources/public_sources.tbz2"
	[6.0DP]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v2.0/sources/public_sources.tbz2"
	[6.2]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/sources/public_sources.tbz2"
)

declare -A DRIVER_URLS=(
    [5.1.3]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/release/jetson_linux_r35.5.0_aarch64.tbz2"
    [5.1.2]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/release/jetson_linux_r35.4.1_aarch64.tbz2"
	[6.0DP]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v2.0/release/jetson_linux_r36.2.0_aarch64.tbz2"
	[6.2]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/release/Jetson_Linux_r36.4.3_aarch64.tbz2"
)

# Default values
JETPACK_VERSION="5.1.3"
DOWNLOAD=true
ACCESS_TOKEN=""
TAG="latest"
SOC="orin"
SKIP_KERNEL_BUILD=false
SKIP_CHROOT_BUILD=false

# Function to show help
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -j, --jetpack VERSION   Specify JetPack version (default: $JETPACK_VERSION)"
	echo "  --access-token TOKEN    Provide the access token (required)"
    echo "  --tag TAG               Specify tag for get_packages.sh (default: $TAG)"
    echo "  --soc SOC               Specify SoC type for jetson_chroot.sh (default: $SOC)"
    echo "						    Available versions: 5.1.3 (L4T ${JETPACK_L4T_MAP[5.1.3]}), 5.1.2 (L4T ${JETPACK_L4T_MAP[5.1.2]})"
	echo "  --skip-kernel-build		Skips building the kernel"
	echo "  --skip-chroot-build		Skips updating and settup up the rootfs in a chroot"
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
        --skip-kernel-build)
            SKIP_KERNEL_BUILD=true
            shift
            ;;
        --skip-chroot-build)
            SKIP_CHROOT_BUILD=true
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

if [[ -z "${JETPACK_L4T_MAP[$JETPACK_VERSION]}" ]]; then
    echo "Error: Unsupported JetPack version. Use --help to see available versions."
    exit 1
fi

if [[ -z "$ACCESS_TOKEN" ]]; then
    echo "Error: --access-token is required."
    exit 1
fi

ROOTFS_FILE="$(basename "${ROOTFS_URLS[$JETPACK_VERSION]}")"
KERNEL_FILE="$(basename "${KERNEL_URLS[$JETPACK_VERSION]}")"
DRIVER_FILE="$(basename "${DRIVER_URLS[$JETPACK_VERSION]}")"

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

TEGRA_DIR="$JETPACK_VERSION"
if [ ! -d "$TEGRA_DIR" ] || [ -z "$(ls -A "$TEGRA_DIR" 2>/dev/null)" ]; then
    sudo mkdir -p "$TEGRA_DIR"
    echo "Extracting driver package: $DRIVER_FILE into $TEGRA_DIR..."
    sudo tar -xjf "$DRIVER_FILE" -C "$TEGRA_DIR"
    echo "Driver package extracted successfully."
fi
TEGRA_DIR="$TEGRA_DIR/Linux_for_Tegra"

if [ ! -d "$TEGRA_DIR/kernel_src" ] || [ -z "$(ls -A "$TEGRA_DIR/kernel_src" 2>/dev/null)" ]; then

	TMP_DIR=$(sudo mktemp -d)
	echo "Extracting public sources: $KERNEL_FILE into $TMP_DIR..."
	sudo tar -xjf "$KERNEL_FILE" -C "$TMP_DIR"
	sudo mkdir -p "$TEGRA_DIR/kernel_src"
	echo "JetPack $JETPACK_VERSION detected, extracting kernel sources"

	if [[ "$JETPACK_VERSION" == "5.1.2" || "$JETPACK_VERSION" == "5.1.3" ]]; then
		sudo tar -xjf "$TMP_DIR/Linux_for_Tegra/source/public/kernel_src.tbz2" -C "$TEGRA_DIR/kernel_src"
	elif [[ "$JETPACK_VERSION" == "6.2" || "$JETPACK_VERSION" == "6.0DP" ]]; then
		sudo tar -xjf "$TMP_DIR/Linux_for_Tegra/source/kernel_src.tbz2" -C "$TEGRA_DIR/kernel_src"

		if [[ -f "$TMP_DIR/Linux_for_Tegra/source/kernel_oot_modules_src.tbz2" ]]; then
			echo "Extracting kernel out-of-tree modules..."
			if [ ! -d "$TEGRA_DIR/kernel_src" ] || [ -z "$(ls -A "$TEGRA_DIR/kernel_src" 2>/dev/null)" ]; then
				sudo tar -xjf "$TMP_DIR/Linux_for_Tegra/source/kernel_oot_modules_src.tbz2" -C "$TEGRA_DIR/kernel_src"
			fi
		else
			echo "Warning: kernel_oot_modules_src.tbz2 not found!"
		fi

		if [[ -f "$TMP_DIR/Linux_for_Tegra/source/nvidia_kernel_display_driver_source.tbz2" ]]; then
			if [ ! -d "$TEGRA_DIR/kernel_src" ]; then
				echo "Extracting NVIDIA kernel display driver source..."
				sudo tar -xjf "$TMP_DIR/Linux_for_Tegra/source/nvidia_kernel_display_driver_source.tbz2" -C "$TEGRA_DIR/kernel_src"
				echo "Extraction completed."
			fi
		else
			echo "Warning: nvidia_kernel_display_driver_source.tbz2 not found!"
		fi

	else
		echo "Warning: Unsupported JetPack version ($JETPACK_VERSION). Skipping additional kernel extraction."
	fi

	echo "Kernel sources extracted successfully."
	rm -rf "$TMP_DIR"
fi

echo "Extracting root filesystem: $ROOTFS_FILE into $TEGRA_DIR/rootfs..."

if [ ! -d "$TEGRA_DIR/rootfs" ] || ( [ "$(ls -A "$TEGRA_DIR/rootfs" | grep -v 'README.txt' | wc -l)" -eq 0 ] ); then
    mkdir -p "$TEGRA_DIR/rootfs"
    sudo tar -xjf "$ROOTFS_FILE" -C "$TEGRA_DIR/rootfs"
    echo "Root filesystem extraction completed."
fi

echo 'export PATH=/usr/local/sbin:/usr/sbin:/sbin:$PATH' | sudo tee $TEGRA_DIR/rootfs/root/.bashrc > /dev/null

echo "Cloning Jetson Linux toolchain into $TEGRA_DIR/toolchain..."
if [ ! -d "$TEGRA_DIR/toolchain" ]; then
    sudo git clone --depth=1 https://github.com/alxhoff/jetson-linux-toolchain "$TEGRA_DIR/toolchain"
fi
echo "Toolchain cloned successfully."

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
FILES=$(curl -s "$GIT_ROOTFS_URL")

# Check if the response is valid JSON
if ! echo "$FILES" | jq empty 2>/dev/null; then
    echo "Error: Failed to retrieve file list or invalid JSON response."
    echo "Response: $FILES"
    exit 1
fi

FILE_URLS=$(echo "$FILES" | jq -r '.[] | select(.type=="file") | .download_url' | grep -v '^$')

if [[ -z "$FILE_URLS" ]]; then
    echo "Error: No valid files found in GitHub response."
    exit 1
fi

echo "Downloading all rootfs scripts into $TEGRA_DIR..."

for FILE in $FILE_URLS; do
    if [[ -z "$FILE" || "$FILE" == "null" ]]; then
        echo "Skipping invalid or empty file URL."
        continue
    fi

    echo "Downloading $(basename "$FILE")..."
    wget --show-progress -P "$TEGRA_DIR/" "$FILE"
done

rm $TEGRA_DIR/setup_tegra_package.sh

echo "All rootfs scripts downloaded successfully."

echo "Setting execute permissions for scripts..."
chmod +x "$TEGRA_DIR/"*.sh

cd $TEGRA_DIR

if [[ "$SKIP_KERNEL_BUILD" == false ]]; then
    sudo ./build_kernel.sh --patch $JETPACK_VERSION --localversion -cartken$JETPACK_VERSION
else
    echo "Skipping kernel build as requested."
fi

echo "Running get_packages.sh with access token and tag: $TAG..."
./get_packages.sh --access-token "$ACCESS_TOKEN" --tag "$TAG"
sudo cp -r packages rootfs/root/

sudo ./setup_rootfs.sh

if [[ "$SKIP_CHROOT_BUILD" == false ]]; then
	echo "Setting up chroot environment for SoC: $SOC..."
	sudo ./jetson_chroot.sh rootfs "$SOC" chroot_setup_commands.txt
else
    echo "Skipping rootfs setup in chroot as requested."
fi

echo "Setup completed successfully!"
