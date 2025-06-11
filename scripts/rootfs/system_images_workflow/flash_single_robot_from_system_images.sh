#!/usr/bin/env bash
set -euo pipefail

# defaults
IMAGES_DIR="robot_images"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_L4T_DIR="$SCRIPT_DIR/cartken_flash/Linux_for_Tegra"
L4T_DIR="$DEFAULT_L4T_DIR"

usage() {
  cat <<EOF
Usage: $0 \
  --robot N \
  [--l4t-dir DIR] \
  [--images-dir DIR]

  --robot       Robot ID to flash
  --l4t-dir     Path to L4T tree (default: $DEFAULT_L4T_DIR)
  --images-dir  Root dir where images live (default: $IMAGES_DIR)
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --robot)      ROBOT="$2";      shift 2;;
    --l4t-dir)    L4T_DIR="$2";    shift 2;;
    --images-dir) IMAGES_DIR="$2"; shift 2;;
    -h|--help)    usage;;
    *)            echo "Unknown arg: $1" >&2; usage;;
  esac
done

: "${ROBOT:?--robot required}"

# ensure paths exist
[[ -d $L4T_DIR ]]    || { echo "❌ L4T dir '$L4T_DIR' not found" >&2; exit 1; }
[[ -d $IMAGES_DIR ]] || { echo "❌ images dir '$IMAGES_DIR' not found" >&2; exit 1; }

# restore images
sudo ./restore_system_images.sh \
  --l4t-dir "$L4T_DIR" \
  --target-images "$IMAGES_DIR/$ROBOT"

# flash device
sudo ./flash_jetson_ALL_sdmmc_partition_qspi.sh \
  --l4t-dir "$L4T_DIR"

echo "✓ robot $ROBOT flashed"

