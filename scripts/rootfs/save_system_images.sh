#!/usr/bin/env bash
set -euo pipefail

# must be root
if [[ $EUID -ne 0 ]]; then
  echo "❌ must be run as root" >&2
  exit 1
fi

usage() {
  cat <<EOF
Usage: $0 --l4t-dir DIR --output DIR

  --l4t-dir   Root of L4T tree to search for .img files
  --output    Directory to copy found .img files into, preserving structure
EOF
  exit 1
}

# parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --l4t-dir) L4T_DIR="$2"; shift 2 ;;
    --output)  OUT_DIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    *)         echo "Unknown arg: $1" >&2; usage ;;
  esac
done

: "${L4T_DIR:?--l4t-dir required}"
: "${OUT_DIR:?--output required}"

[[ -d $L4T_DIR ]] || { echo "❌ L4T directory '$L4T_DIR' not found"; exit 1; }
mkdir -p "$OUT_DIR"

# find absolute .img files and copy while preserving relative structure
find "$L4T_DIR" -type f -name '*.img' -print0 | while IFS= read -r -d '' IMG; do
  rel="${IMG#"$L4T_DIR"/}"
  dst="$OUT_DIR/$rel"
  mkdir -p "$(dirname "$dst")"
  cp -- "$IMG" "$dst"
done

echo "✓ All .img files from '$L4T_DIR' saved under '$OUT_DIR' with original structure"

