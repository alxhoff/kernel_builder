#!/bin/bash

# Function to display help
show_help() {
  cat <<EOF
Usage: $0 [OPTIONS] <TAR_FILE_PATH>

Options:
  --help                Show this help message and exit.

Arguments:
  TAR_FILE_PATH         Full path to the tar file containing the rootfs.

Description:
  This script:
    - Requires root privileges.
    - Extracts the specified tar file, preserving permissions, into a folder named 'rootfs' in the same directory as this script.
    - Calls 'jetson_chroot.sh rootfs' to access the rootfs.

Requirements:
  - Ensure 'jetson_chroot.sh' is available in the same directory as this script.
  - The script must be run as root.

Examples:
  Run the script:
    sudo $0 /path/to/rootfs.tar.gz

  Show help:
    $0 --help

EOF
}

# Check for --help option
if [[ "$1" == "--help" ]]; then
  show_help
  exit 0
fi

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root."
  exit 1
fi

# Check if a tar file path is provided
if [ -z "$1" ]; then
  echo "Error: No tar file path provided."
  echo "Run '$0 --help' for usage information."
  exit 1
fi

TAR_PATH="$1"

# Validate the tar file exists
if [ ! -f "$TAR_PATH" ]; then
  echo "Error: File not found at $TAR_PATH"
  exit 1
fi

# Get the directory of the script
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
ROOTFS_DIR="$SCRIPT_DIR/rootfs"

# Extract the tar file to the 'rootfs' folder in the script's directory
echo "Extracting rootfs to $ROOTFS_DIR..."
mkdir -p "$ROOTFS_DIR"

# Extract the tarball preserving permissions
tar --strip-components=1 -xpf "$TAR_PATH" -C "$ROOTFS_DIR" || {
  echo "Error: Failed to extract the tar file."
  exit 1
}

echo "Extraction completed."

# Call jetson_chroot.sh rootfs
echo "Calling jetson_chroot.sh to access rootfs..."
JETSON_CHROOT_PATH="$SCRIPT_DIR/jetson_chroot.sh"
if [ ! -f "$JETSON_CHROOT_PATH" ]; then
  echo "Error: jetson_chroot.sh not found in the script directory."
  exit 1
fi

bash "$JETSON_CHROOT_PATH" "$ROOTFS_DIR" || {
  echo "Error: jetson_chroot.sh failed."
  exit 1
}

echo "Rebuild completed successfully!"
exit 0

