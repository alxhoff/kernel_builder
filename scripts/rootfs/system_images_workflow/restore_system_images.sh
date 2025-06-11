#!/usr/bin/env bash
set -euo pipefail

# defaults
default_l4t_dir="cartken_flash/Linux_for_Tegra/rootfs"
default_images_dir="robot_images"

# initial values
L4T_DIR="$default_l4t_dir"
IMAGES_BASE="$default_images_dir"
ROBOT_ID=""

usage() {
  cat <<EOF
Usage: sudo $0 \
  [--l4t-dir DIR] \
  [--images-dir DIR] \
  --robot N

  --l4t-dir      Root of L4T tree (default: $default_l4t_dir)
  --images-dir   Base directory where images live (default: $default_images_dir)
  --robot        Robot number to restore
EOF
  exit 1
}

# parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --l4t-dir)
      L4T_DIR="$2"; shift 2;;
    --images-dir)
      IMAGES_BASE="$2"; shift 2;;
    --robot)
      ROBOT_ID="$2"; shift 2;;
    -h|--help)
      usage;;
    *)
      echo "Unknown arg: $1" >&2; usage;;
  esac
done

# require args
: "${ROBOT_ID:?--robot required}"

# must run as root
test "$EUID" -eq 0 || { echo "❌ must be run as root" >&2; exit 1; }

# validate directories
[[ -d "$L4T_DIR" ]]    || { echo "❌ L4T dir '$L4T_DIR' not found" >&2; exit 1; }

IMAGES_DIR="$IMAGES_BASE/$ROBOT_ID"
[[ -d "$IMAGES_DIR" ]] || { echo "❌ images dir '$IMAGES_DIR' not found" >&2; exit 1; }

# restore images
echo "Restoring .img files from '$IMAGES_DIR' into '$L4T_DIR'..."
find "$IMAGES_DIR" -type f -name '*.img' -print0 | while IFS= read -r -d '' img; do
  rel_path="${img#${IMAGES_DIR}/}"
  dest_path="$L4T_DIR/$rel_path"
  mkdir -p "$(dirname "$dest_path")"
  cp -- "$img" "$dest_path"
done

echo "✓ All .img files restored into '$L4T_DIR'"

