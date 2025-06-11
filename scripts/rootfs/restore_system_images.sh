#!/usr/bin/env bash
set -euo pipefail

# must be root
if [[ $EUID -ne 0 ]]; then
  echo "❌ must be run as root" >&2
  exit 1
fi

usage() {
  cat <<EOF
Usage: $0 --l4t-dir DIR --target-images DIR

  --l4t-dir       Root of L4T tree to restore .img files into
  --target-images Backup folder containing .img files (with same structure)
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --l4t-dir)       L4T_DIR="$2"; shift 2 ;;
    --target-images) IMG_DIR="$2"; shift 2 ;;
    -h|--help)       usage ;;
    *)               echo "Unknown arg: $1" >&2; usage ;;
  esac
done

: "${L4T_DIR:?--l4t-dir required}"
: "${IMG_DIR:?--target-images required}"

[[ -d $L4T_DIR ]] || { echo "❌ L4T directory '$L4T_DIR' not found"; exit 1; }
[[ -d $IMG_DIR ]] || { echo "❌ target-images directory '$IMG_DIR' not found"; exit 1; }

# make paths absolute
L4T_DIR=$(realpath "$L4T_DIR")
IMG_DIR=$(realpath "$IMG_DIR")

find "$IMG_DIR" -type f -name '*.img' -print0 | while IFS= read -r -d '' IMG; do
  rel=${IMG#"$IMG_DIR"/}
  dest="$L4T_DIR/$rel"
  mkdir -p "$(dirname "$dest")"
  cp -- "$IMG" "$dest"
done

echo "✓ Restored all .img files from '$IMG_DIR' into '$L4T_DIR'"

