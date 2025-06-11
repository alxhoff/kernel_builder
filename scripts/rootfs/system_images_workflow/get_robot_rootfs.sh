#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
FILE_ID="1-MEJNanz2eWXEhm5JC2tyiCAf8BLX_9h"
TAR_NAME="cartken_flash.tar.gz"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACT_DIR="$SCRIPT_DIR/cartken_flash"
L4T_DIR="$EXTRACT_DIR/Linux_for_Tegra"

usage() {
  cat <<EOF
Usage: $0 [--tar PATH]

Options:
  --tar <path>    Use a local tarball instead of downloading via gdown
  -h, --help      Show this help message and exit

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
  if grep -qi ubuntu /etc/os-release; then
	  sudo apt-get update -y
	  sudo apt-get install -y python3-pip curl
  fi
  # install gdown
  if python3 -c 'import sys; exit(0) if (sys.version_info.major, sys.version_info.minor) >= (3,10) else exit(1)'; then
    pip install --break-system-packages --upgrade gdown
  else
    pip install --upgrade gdown
  fi
  gdown "$FILE_ID" -O "$SCRIPT_DIR/$TAR_NAME"
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

echo "Done. L4T directory is at: $L4T_DIR"

