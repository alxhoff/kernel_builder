```bash
#!/usr/bin/env bash
set -euo pipefail

# defaults
default_vpn_dir="robot_credentials"
default_images_dir="robot_images"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
default_l4t_dir="$SCRIPT_DIR/cartken_flash/Linux_for_Tegra"

VPN_DIR="$default_vpn_dir"
IMAGES_DIR="$default_images_dir"
L4T_DIR="$default_l4t_dir"

usage() {
  cat <<EOF
Usage: $0 \
  --robots R1,R2,... \
  --password PASS \
  [--l4t-dir DIR] \
  [--vpn-output DIR] \
  [--images-dir DIR]

  --robots       Comma-separated list of robot IDs
  --password     Password for sshpass
  --l4t-dir      Path to L4T tree (default: $default_l4t_dir)
  --vpn-output   Where to put pulled credentials (default: $default_vpn_dir)
  --images-dir   Root dir for per-robot images (default: $default_images_dir)
EOF
  exit 1
}

# parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --robots)     ROBOTS="$2";    shift 2;;
    --password)   PASSWORD="$2";  shift 2;;
    --l4t-dir)    L4T_DIR="$2";   shift 2;;
    --vpn-output) VPN_DIR="$2";   shift 2;;
    --images-dir) IMAGES_DIR="$2";shift 2;;
    -h|--help)    usage;;
    *)            echo "Unknown arg: $1" >&2; usage;;
  esac
done

: "${ROBOTS:?--robots required}"
: "${PASSWORD:?--password required}"

# ensure L4T exists, else fetch it
echo "Using L4T dir: $L4T_DIR"
if [[ ! -d $L4T_DIR ]]; then
  echo "L4T directory '$L4T_DIR' not found; running get_robot_rootfs.sh..."
  "${SCRIPT_DIR}/get_robot_rootfs.sh"
  if [[ ! -d $L4T_DIR ]]; then
    echo "❌ failed to obtain L4T directory at '$L4T_DIR'" >&2
    exit 1
  fi
fi

# pull creds
echo "Pulling credentials into: $VPN_DIR"
./get_robot_credentials.sh \
  --robots "$ROBOTS" \
  --password "$PASSWORD" \
  --output "$VPN_DIR"

# create images per robot
IFS=',' read -ra RS <<< "$ROBOTS"
for R in "${RS[@]}"; do
  echo "=== setting up rootfs for robot $R ==="
  sudo ./setup_rootfs_with_robot_number.sh \
    --vpn-credentials "$VPN_DIR" \
    --rootfs-dir "$L4T_DIR/rootfs" \
    --robot "$R"

  echo "=== creating system images for robot $R ==="
  sudo ./create_system_images.sh

  echo "=== saving system images for robot $R ==="
  sudo ./save_system_images.sh \
    --l4t-dir "$L4T_DIR" \
    --output "$IMAGES_DIR/$R"
done

echo "✓ all images created under $IMAGES_DIR"
```

