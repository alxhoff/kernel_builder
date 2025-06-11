#!/usr/bin/env bash
set -euo pipefail

# defaults
default_l4t_dir="cartken_flash/Linux_for_Tegra"
default_output_dir="system_images"

# init with defaults
L4T_DIR="$default_l4t_dir"
OUTPUT_BASE="$default_output_dir"
ROBOT_ID=""

usage() {
  cat <<EOF
Usage: sudo $0 \
  [--l4t-dir DIR] \
  [--output DIR] \
  --robot N

  --l4t-dir    Rootfs directory (default: $default_l4t_dir)
  --output     Base directory to save images (default: $default_output_dir)
  --robot      Robot number (used to create subdir under --output)
EOF
  exit 1
}

# parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --l4t-dir)
      L4T_DIR="$2"; shift 2;;
    --output)
      OUTPUT_BASE="$2"; shift 2;;
    --robot)
      ROBOT_ID="$2"; shift 2;;
    -h|--help)
      usage;;
    *)
      echo "Unknown arg: $1" >&2; usage;;
  esac
done

# require robot
: "${ROBOT_ID:?--robot required}"

# must run as root
test "$EUID" -eq 0 || { echo "❌ must be run as root" >&2; exit 1; }

# validate L4T_DIR
test -d "$L4T_DIR" || { echo "❌ L4T directory '$L4T_DIR' not found" >&2; exit 1; }

# prepare target dir
TARGET_DIR="$OUTPUT_BASE/$ROBOT_ID"
mkdir -p "$TARGET_DIR"

echo "Saving .img files from '$L4T_DIR' to '$TARGET_DIR'..."

# find and copy .img files without crossing into other mounts
default_opts=(-xdev -type f -name '*.img' -print0)
find "$L4T_DIR" "${default_opts[@]}" | \
while IFS= read -r -d '' IMG; do
  REL_PATH="${IMG#${L4T_DIR}/}"
  DEST_DIR="$TARGET_DIR/$(dirname "$REL_PATH")"
  mkdir -p "$DEST_DIR"
  cp -- "$IMG" "$DEST_DIR/"
done

echo "✓ All .img files saved under '$TARGET_DIR'"
