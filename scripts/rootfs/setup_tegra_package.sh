#!/bin/bash

set -ex

if ! command -v jq &> /dev/null
then
    echo "jq could not be found, please install it first"
    exit
fi

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

# --- Helper Functions ---
PROMPT=false
prompt_user() {
    if [ "$PROMPT" = true ]; then
        echo "------------------------------------------------------"
        echo "Script paused. Press Enter to continue..."
        read -r
        echo "------------------------------------------------------"
    fi
}

# Define JetPack versions and corresponding L4T versions
declare -A JETPACK_L4T_MAP=(
    [5.1.2]=35.4.1
    [5.1.3]=35.5.0
	[5.1.4]=35.6.0
	[5.1.5]=35.6.1
	[6.0DP]=36.2
	[6.1]=36.4
	[6.2]=36.4.3
)

# Define URLs for the sources
declare -A ROOTFS_URLS=(
    [5.1.2]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/release/tegra_linux_sample-root-filesystem_r35.4.1_aarch64.tbz2"
    [5.1.3]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/release/tegra_linux_sample-root-filesystem_r35.5.0_aarch64.tbz2"
	[5.1.4]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.0/release/tegra_linux_sample-root-filesystem_r35.6.0_aarch64.tbz2"
	[5.1.5]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.1/tegra_linux_sample-root-filesystem_r35.6.1_aarch64.tbz2"
	[6.0DP]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v2.0/release/tegra_linux_sample-root-filesystem_r36.2.0_aarch64.tbz2"
	[6.1]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.0/release/Tegra_Linux_Sample-Root-Filesystem_R36.4.0_aarch64.tbz2"
	[6.2]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/release/Tegra_Linux_Sample-Root-Filesystem_r36.4.3_aarch64.tbz2"
)

declare -A KERNEL_URLS=(
    [5.1.2]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/sources/public_sources.tbz2"
    [5.1.3]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/sources/public_sources.tbz2"
	[5.1.4]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.0/sources/public_sources.tbz2"
	[5.1.5]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.1/sources/public_sources.tbz2"
	[6.0DP]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v2.0/sources/public_sources.tbz2"
	[6.1]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.0/sources/public_sources.tbz2"
	[6.2]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/sources/public_sources.tbz2"
)

declare -A DRIVER_URLS=(
    [5.1.2]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/release/jetson_linux_r35.4.1_aarch64.tbz2"
    [5.1.3]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/release/jetson_linux_r35.5.0_aarch64.tbz2"
	[5.1.4]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.0/release/jetson_linux_r35.6.0_aarch64.tbz2"
	[5.1.5]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.1/release/jetson_linux_r35.6.1_aarch64.tbz2"
	[6.0DP]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v2.0/release/jetson_linux_r36.2.0_aarch64.tbz2"
	[6.1]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.0/release/Jetson_Linux_R36.4.0_aarch64.tbz2"
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
SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to show help
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -j, --jetpack VERSION   Specify JetPack version (default: $JETPACK_VERSION)"
	echo "  --access-token TOKEN    Provide the access token (required)"
    echo "  --tag TAG               Specify tag for get_packages.sh (default: $TAG)"
    echo "  --soc SOC               Specify SoC type for jetson_chroot.sh (default: $SOC)"
	echo "  --skip-kernel-build		Skips building the kernel"
	echo "  --skip-chroot-build		Skips updating and settup up the rootfs in a chroot"
    echo "  --no-download           Use existing .tbz2 files instead of downloading"
	echo "  --just-clone		    Only pulls the sources, nothing more"
    echo "  --prompt                Prompt user to press Enter at each major step"
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
		--just-clone)
			JUST_CLONE=true
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
        --prompt)
            PROMPT=true
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

TEGRA_BASE_DIR="$SCRIPT_DIRECTORY/$JETPACK_VERSION"
TEGRA_DIR="$TEGRA_BASE_DIR/Linux_for_Tegra"

prompt_user

if [ ! -d "$TEGRA_DIR" ] || [ -z "$(ls -A "$TEGRA_DIR" 2>/dev/null)" ]; then
	if [ "$DOWNLOAD" = true ]; then
		echo "Downloading required BSP files for JetPack $JETPACK_VERSION (L4T ${JETPACK_L4T_MAP[$JETPACK_VERSION]})..."
		wget -c "${DRIVER_URLS[$JETPACK_VERSION]}" -O "$DRIVER_FILE"
	else
		echo "Skipping download, using local files."
		if [ ! -f "$DRIVER_FILE" ]; then
			echo "Error: Expected file $DRIVER_FILE not found."
			exit 1
		fi
	fi

	prompt_user

	sudo mkdir -p "$TEGRA_BASE_DIR"
	echo "Extracting driver package: $DRIVER_FILE into $TEGRA_BASE_DIR..."
	sudo tar -xjf "$DRIVER_FILE" -C "$TEGRA_BASE_DIR"
	echo "Driver package extracted successfully."
fi

if [ -f "$TEGRA_DIR/tools/l4t_flash_prerequisites.sh" ]; then
  echo "Running l4t_flash_prerequisites.sh..."
  (cd "$TEGRA_DIR" && ./tools/l4t_flash_prerequisites.sh)
fi

prompt_user

if [ ! -d "$TEGRA_DIR/kernel_src" ] || [ -z "$(ls -A "$TEGRA_DIR/kernel_src" 2>/dev/null)" ]; then

	if [ "$DOWNLOAD" = true ]; then
		echo "Downloading required kernel source files for JetPack $JETPACK_VERSION (L4T ${JETPACK_L4T_MAP[$JETPACK_VERSION]})..."
		wget "${KERNEL_URLS[$JETPACK_VERSION]}" -O "$KERNEL_FILE"
	else
		echo "Skipping download, using local files."
		if [ ! -f "$KERNEL_FILE" ]; then
			echo "Error: Expected file $KERNEL_FILE not found."
			exit 1
		fi
	fi

	prompt_user

	TMP_DIR=$(sudo mktemp -d)
	echo "Extracting public sources: $KERNEL_FILE into $TMP_DIR..."
	sudo tar -xjf "$KERNEL_FILE" -C "$TMP_DIR"
	sudo mkdir -p "$TEGRA_DIR/kernel_src"
	echo "JetPack \"$JETPACK_VERSION\" detected, extracting kernel sources"

	case "$JETPACK_VERSION" in
		5.1.2|5.1.3|5.1.4|5.1.5)
			sudo tar -xjf "$TMP_DIR/Linux_for_Tegra/source/public/kernel_src.tbz2" -C "$TEGRA_DIR/kernel_src"

			if [[ -f "$TMP_DIR/Linux_for_Tegra/source/public/nvidia_kernel_display_driver_source.tbz2" ]]; then
				if [ ! -d "$TEGRA_DIR/kernel_src/nvdisplay" ]; then
					echo "Extracting NVIDIA kernel display driver source..."
					sudo tar -xjf "$TMP_DIR/Linux_for_Tegra/source/public/nvidia_kernel_display_driver_source.tbz2" -C "$TEGRA_DIR/kernel_src"
					echo "Extraction completed."
				fi
			else
				echo "Warning: nvidia_kernel_display_driver_source.tbz2 not found!"
			fi
			;;
		6.0DP|6.1|6.2)
			sudo tar -xjf "$TMP_DIR/Linux_for_Tegra/source/kernel_src.tbz2" -C "$TEGRA_DIR/kernel_src"

			if [[ -f "$TMP_DIR/Linux_for_Tegra/source/kernel_oot_modules_src.tbz2" ]]; then
				echo "Extracting kernel out-of-tree modules..."
				if [ ! -d "$TEGRA_DIR/kernel_src/nvidia-oot" ] || [ -z "$(ls -A "$TEGRA_DIR/kernel_src" 2>/dev/null)" ]; then
					sudo tar -xjf "$TMP_DIR/Linux_for_Tegra/source/kernel_oot_modules_src.tbz2" -C "$TEGRA_DIR/kernel_src"
					echo "OOT Modules extracted"
				fi
			else
				echo "Warning: kernel_oot_modules_src.tbz2 not found!"
			fi

			if [[ -f "$TMP_DIR/Linux_for_Tegra/source/nvidia_kernel_display_driver_source.tbz2" ]]; then
				if [ ! -d "$TEGRA_DIR/kernel_src/nvdisplay" ]; then
					echo "Extracting NVIDIA kernel display driver source..."
					sudo tar -xjf "$TMP_DIR/Linux_for_Tegra/source/nvidia_kernel_display_driver_source.tbz2" -C "$TEGRA_DIR/kernel_src"
					echo "Extraction completed."
				fi
			else
				echo "Warning: nvidia_kernel_display_driver_source.tbz2 not found!"
			fi
			;;
		*)
			echo "Error: Unsupported target BSP version. Supported versions are 5.1.2–5.1.5, 6.0DP, and 6.2."
			exit 1
			;;
	esac

	echo "Kernel sources extracted successfully."
	rm -rf "$TMP_DIR"
fi

if [ ! -d "$TEGRA_DIR/rootfs" ] || ( [ "$(ls -A "$TEGRA_DIR/rootfs" | grep -v 'README.txt' | wc -l)" -eq 0 ] ); then
	if [ "$DOWNLOAD" = true ]; then
		echo "Downloading required rootfs files for JetPack $JETPACK_VERSION (L4T ${JETPACK_L4T_MAP[$JETPACK_VERSION]})..."
		wget -c "${ROOTFS_URLS[$JETPACK_VERSION]}" -O "$ROOTFS_FILE"
	else
		echo "Skipping download, using local files."
		if [ ! -f "$ROOTFS_FILE" ]; then
			echo "Error: Expected file $ROOTFS_FILE not found."
			exit 1
		fi
	fi

	prompt_user

	mkdir -p "$TEGRA_DIR/rootfs"
	echo "Extracting root filesystem: $ROOTFS_FILE into $TEGRA_DIR/rootfs..."
	sudo tar -xjf "$ROOTFS_FILE" -C "$TEGRA_DIR/rootfs"
	echo "Root filesystem extraction completed."
fi

echo 'export PATH=/usr/local/sbin:/usr/sbin:/sbin:$PATH' | sudo tee $TEGRA_DIR/rootfs/root/.bashrc > /dev/null

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

prompt_user

# if [[ "$SKIP_CHROOT_BUILD" == false ]]; then
#     echo "Setting up chroot environment for SoC: $SOC..."
#     sudo $TEGRA_DIR/jetson_chroot.sh $TEGRA_DIR/rootfs "$SOC" essential_chroot_setup_commands.txt
# else
#     echo "Skipping rootfs setup in chroot as requested."
# fi

rm $TEGRA_DIR/setup_tegra_package.sh
echo "Setting execute permissions for scripts..."
chmod +x "$TEGRA_DIR/"*.sh
echo "All rootfs scripts downloaded successfully."

prompt_user

cd $TEGRA_DIR
echo "Setting up rootfs with nvidia binaries and default user"
echo "Removing existing device nodes before setup..."
sudo rm -f "$TEGRA_DIR/rootfs/dev/random"
sudo rm -f "$TEGRA_DIR/rootfs/dev/urandom"
sudo $TEGRA_DIR/setup_rootfs.sh --l4t-dir $TEGRA_DIR

prompt_user

echo "Running get_packages.sh with access token and tag: $TAG..."
$TEGRA_DIR/get_packages.sh --access-token "$ACCESS_TOKEN" --tag "$TAG"
sudo cp -r $TEGRA_DIR/packages $TEGRA_DIR/rootfs/root/

prompt_user

if [[ "$SKIP_CHROOT_BUILD" == false ]]; then
	echo "Setting up chroot environment for SoC: $SOC..."
	sudo $TEGRA_DIR/jetson_chroot.sh rootfs "$SOC" chroot_setup_commands.txt
else
	echo "Skipping rootfs setup in chroot as requested."
fi

prompt_user

echo "Getting pinmux files"
sudo $TEGRA_DIR/get_pinmux.sh --l4t-dir $TEGRA_DIR --jetpack-version $JETPACK_VERSION

if [[ "$JUST_CLONE" == true ]]; then
	exit 1
fi

prompt_user

if [[ "$SKIP_KERNEL_BUILD" == false ]]; then
	echo "Cloning Jetson Linux toolchain into $TEGRA_DIR/toolchain..."
	if [ ! -d "$TEGRA_DIR/toolchain" ]; then
		sudo git clone --config core.symlinks=true --depth=1 https://github.com/alxhoff/jetson-linux-toolchain "$TEGRA_DIR/toolchain"
	fi
	echo "Toolchain cloned successfully."

	prompt_user

	echo "Building kernel"
	case "$JETPACK_VERSION" in
		5.1.2|5.1.3|5.1.4|5.1.5)
			sudo $TEGRA_DIR/build_kernel.sh --patch $JETPACK_VERSION --localversion -cartken$JETPACK_VERSION

			prompt_user

			echo "Building display driver"
			echo "sudo "$TEGRA_DIR/build_display_driver.sh" --toolchain "$TEGRA_DIR/toolchain" --kernel-sources "$TEGRA_DIR/kernel_src" --target-bsp "$JETPACK_VERSION""
			sudo "$TEGRA_DIR/build_display_driver.sh" --toolchain "$TEGRA_DIR/toolchain" --kernel-sources "$TEGRA_DIR/kernel_src" --target-bsp "$JETPACK_VERSION"

			prompt_user

			DISPLAY_DRIVER_DIR="$TEGRA_DIR/jetson_display_driver"
			ROOTFS_DIR="$TEGRA_DIR/rootfs"
			ROOTFS_MODULES_DIR="$ROOTFS_DIR/lib/modules"
			KERNEL_VERSION=$(find "$DISPLAY_DRIVER_DIR" -type f -name "Image" -exec strings {} \; | grep -m1 -Eo 'Linux version [^ ]+' | awk '{print $3}')
			ROOTFS_TARGET_MODULES_DIR="$ROOTFS_MODULES_DIR/$KERNEL_VERSION/extra/opensrc-disp"
			echo "Copying display driver into our kernel at $ROOTFS_TARGET_MODULES_DIR"
			mkdir -p "$ROOTFS_TARGET_MODULES_DIR"
			NVDISPLAY_MOD_DIR=$(find "$DISPLAY_DRIVER_DIR" -type f -name "nvidia.ko" -exec dirname {} \; | head -n1)
			echo "nvidia.ko found in: $NVDISPLAY_MOD_DIR"
			cp "$NVDISPLAY_MOD_DIR"/*.ko "$ROOTFS_TARGET_MODULES_DIR"

			echo "Running depmod on $KERNEL_VERSION for rootfs: $ROOTFS_DIR"
			depmod -b "$ROOTFS_DIR" "$KERNEL_VERSION"
			;;
		6.0DP|6.1|6.2)
			sudo $TEGRA_DIR/build_kernel_jp6.sh --patch $JETPACK_VERSION --localversion -cartken$JETPACK_VERSION
			;;
		*)
			echo "Error: Unsupported JetPack version for kernel build."
			exit 1
			;;
	esac
else
	echo "Skipping kernel build as requested."
fi

echo "Setup completed successfully!"
