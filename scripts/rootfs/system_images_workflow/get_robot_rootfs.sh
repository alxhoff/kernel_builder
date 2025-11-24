#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
default_file_id="1-MEJNanz2eWXEhm5JC2tyiCAf8BLX_9h"
FILE_ID="$default_file_id"
TAR_NAME="cartken_flash.tar.gz"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACT_DIR="$SCRIPT_DIR/cartken_flash"
L4T_DIR="$EXTRACT_DIR/Linux_for_Tegra"

usage() {
  cat <<EOF
Usage: $0 [--tar PATH] [--rootfs-gid GID]

Options:
  --tar <path>        Use a local tarball instead of downloading via gdown
  --rootfs-gid <gid>  Google Drive file ID for the rootfs tarball (default: $default_file_id)
  -h, --help          Show this help message and exit

This script downloads (or uses a provided) flash bundle and extracts it
into the "cartken_flash" folder under the script's directory.
EOF
  exit 1
}

# parse args
TAR_FILE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --tar)
      TAR_FILE="$2"
      shift 2
      ;;
    --rootfs-gid)
      FILE_ID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

# ensure extract dir
mkdir -p "$EXTRACT_DIR"

# if already extracted, skip
if [[ -d "$L4T_DIR" ]]; then
  echo "Skipping extraction, L4T tree already exists at: $L4T_DIR"
  exit 0
fi

# download if needed
if [[ -z "$TAR_FILE" ]]; then
  echo "No tarball provided; downloading via gdown..."

  # Determine which python executable to use for pip, favoring python3.8
  PYTHON_EXE="python3"
  if command -v python3.8 &> /dev/null; then
      PYTHON_EXE="python3.8"
  fi
  echo "Using python executable: $PYTHON_EXE"

  if grep -qi ubuntu /etc/os-release; then
	  sudo apt-get update -y
	  sudo apt-get install --reinstall -y python3-pip python3-setuptools python3-distutils curl
  fi
  # Check if the tarball already exists
  if [[ -f "$SCRIPT_DIR/$TAR_NAME" ]]; then
    echo "Tarball '$SCRIPT_DIR/$TAR_NAME' already exists; skipping download."
  else
    # install gdown
    echo "Installing gdown"
    if "$PYTHON_EXE" -m pip install --help 2>&1 | grep -q -- '--break-system-packages'; then
      "$PYTHON_EXE" -m pip install --break-system-packages --upgrade gdown --user
    else
      "$PYTHON_EXE" -m pip install --upgrade gdown --user
    fi
    export PATH="$HOME/.local/bin:$PATH"
    "$PYTHON_EXE" -m gdown "$FILE_ID" -O "$SCRIPT_DIR/$TAR_NAME"
  fi
  TAR_FILE="$SCRIPT_DIR/$TAR_NAME"
fi

# extract bundle
echo "Extracting $TAR_FILE into $EXTRACT_DIR..."
if tar -xvzf "$TAR_FILE" -C "$EXTRACT_DIR"; then
  echo "Extraction with gzip succeeded."
else
  echo "Gzip extraction failed; trying plain tar..."
  tar -xvf "$TAR_FILE" -C "$EXTRACT_DIR"
  echo "Fallback extraction succeeded."
fi

if grep -qi ubuntu /etc/os-release; then
  echo "Installing prerequisites"
  chmod +x "$L4T_DIR/tools/l4t_flash_prerequisites.sh"
  sudo bash "$L4T_DIR/tools/l4t_flash_prerequisites.sh"
fi

echo "Done. L4T directory is at: $L4T_DIR"

