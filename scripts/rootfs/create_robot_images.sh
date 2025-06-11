#!/usr/bin/env bash
set -euo pipefail

# defaults
VPN_DIR="robot_credentials"
IMAGES_DIR="robot_images"

usage() {
  cat <<EOF
Usage: $0 \
  --robots R1,R2,... \
  --password PASS \
  --l4t-dir DIR \
  [--vpn-output DIR] \
  [--images-dir DIR]

  --robots       Comma-separated list of robot IDs
  --password     Password for sshpass
  --l4t-dir      Path to L4T tree (e.g. 5.1.5/Linux_for_Tegra)
  --vpn-output   (optional) Where to put pulled credentials (default: $VPN_DIR)
  --images-dir   (optional) Root dir for per-robot images (default: $IMAGES_DIR)
EOF
  exit 1
}

# parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --robots)     ROBOTS="$2";     shift 2;;
    --password)   PASSWORD="$2";   shift 2;;
    --l4t-dir)    L4T_DIR="$2";    shift 2;;
    --vpn-output) VPN_DIR="$2";    shift 2;;
    --images-dir) IMAGES_DIR="$2"; shift 2;;
    -h|--help)    usage;;
    *)            echo "Unknown arg: $1" >&2; usage;;
  esac
done

: "${ROBOTS:?--robots required}"
: "${PASSWORD:?--password required}"
: "${L4T_DIR:?--l4t-dir required}"

# 1) pull creds
./get_robot_credentials.sh \
  --robots "$ROBOTS" \
  --password "$PASSWORD" \
  --output "$VPN_DIR"

# split and loop
IFS=',' read -ra RS <<< "$ROBOTS"
for R in "${RS[@]}"; do
  echo "=== setting up rootfs for robot $R ==="
  sudo ./setup_rootfs_with_robot_number.sh \
    --vpn-credentials "$VPN_DIR" \
    --rootfs-dir "$L4T_DIR/rootfs" \
    --robot "$R"

  echo "=== saving system images for robot $R ==="
  sudo ./save_system_images.sh \
    --l4t-dir "$L4T_DIR" \
    --output "$IMAGES_DIR/$R"
done

echo "✓ all images created under $IMAGES_DIR"

