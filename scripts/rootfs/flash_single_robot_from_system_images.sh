#!/usr/bin/env bash
set -euo pipefail

# default
IMAGES_DIR="robot_images"

usage() {
  cat <<EOF
Usage: $0 \
  --robot N \
  --l4t-dir DIR \
  [--images-dir DIR]

  --robot       Robot ID to flash
  --l4t-dir     Path to L4T tree (e.g. 5.1.5/Linux_for_Tegra)
  --images-dir  (optional) Root dir where images live (default: $IMAGES_DIR)
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
: "${L4T_DIR:?--l4t-dir required}"

# restore images
sudo ./restore_system_images.sh \
  --l4t-dir "$L4T_DIR" \
  --target-images "$IMAGES_DIR/$ROBOT"

# flash device
sudo ./flash_jetson_ALL_sdmmc_partition_qspi.sh \
  --l4t-dir "$L4T_DIR"

echo "✓ robot $ROBOT flashed"

