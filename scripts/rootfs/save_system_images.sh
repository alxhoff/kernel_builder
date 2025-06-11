#!/usr/bin/env bash
set -euo pipefail

# defaults
default_output_dir="system_images"

tmp_output_dir="$default_output_dir"
robot_id=""

usage() {
  cat <<EOF
Usage: $0 \
  --l4t-dir DIR \
  --output DIR \
  --robot N

  --l4t-dir    Root of L4T tree to search for .img files
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
      tmp_output_dir="$2"; shift 2;;
    --robot)
      robot_id="$2"; shift 2;;
    -h|--help)
      usage;;
    *)
      echo "Unknown arg: $1" >&2; usage;;
  esac
done

: "${L4T_DIR:?--l4t-dir required}"
: "${robot_id:?--robot required}"

output_dir="$tmp_output_dir/$robot_id"

# ensure L4T exists
[[ -d "$L4T_DIR" ]] || { echo "❌ L4T directory '$L4T_DIR' not found" >&2; exit 1; }

# create output subdir
mkdir -p "$output_dir"

echo "Saving .img files from '$L4T_DIR' to '$output_dir'..."

# find and copy preserving structure
find "$L4T_DIR" -type f -name '*.img' -print0 | \
  while IFS= read -r -d '' img; do
    rel_path="${img#${L4T_DIR}/}"
    dest_dir="${output_dir}/$(dirname "$rel_path")"
    mkdir -p "$dest_dir"
    cp -- "$img" "$dest_dir/"
  done

echo "✓ All .img files saved under '$output_dir'"

