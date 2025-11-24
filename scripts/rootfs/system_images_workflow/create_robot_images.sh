#!/usr/bin/env bash
set -euo pipefail

# defaults
default_vpn_dir="robot_credentials"
default_images_dir="robot_images"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
default_l4t_dir="$SCRIPT_DIR/cartken_flash/Linux_for_Tegra"

# init with defaults
VPN_DIR="$default_vpn_dir"
IMAGES_DIR="$default_images_dir"
L4T_DIR="$default_l4t_dir"
CRED_ZIP=""
HAVE_CREDENTIALS=false
ROOTFS_GID=""

usage() {
  cat <<EOF
Usage: $0 \
  --robots R1,R2,... \
  --password PASS \
  [--l4t-dir DIR] \
  [--vpn-output DIR] \
  [--images-dir DIR] \
  [--credentials-zip ZIP] \
  [--have-credentials] \
  [--rootfs-gid GID]

  --robots           Comma-separated list of robot IDs (required)
  --password         Password for sshpass (required)
  --l4t-dir          Path to L4T tree (default: $default_l4t_dir)
  --vpn-output       Where to put pulled credentials (default: $default_vpn_dir)
  --images-dir       Root dir for per-robot images (default: $default_images_dir)
  --credentials-zip  Zip containing credentials; if set, unzip into --vpn-output and skip fetching
  --have-credentials For the case that you have already added the robot's credentials to $default_vpn_dir
  --rootfs-gid       Google Drive file ID for the rootfs tarball
EOF
  exit 1
}

# parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --robots)         ROBOTS="$2";       shift 2;;
    --password)       PASSWORD="$2";     shift 2;;
    --l4t-dir)        L4T_DIR="$2";      shift 2;;
    --vpn-output)     VPN_DIR="$2";      shift 2;;
    --images-dir)     IMAGES_DIR="$2";   shift 2;;
    --credentials-zip)CRED_ZIP="$2";     shift 2;;
	--have-credentials) HAVE_CREDENTIALS=true; shift 1;;
    --rootfs-gid)     ROOTFS_GID="$2";   shift 2;;
    -h|--help)        usage;;
    *)                echo "Unknown arg: $1" >&2; usage;;
  esac
done

# validate required
: "${ROBOTS:?--robots required}"
: "${PASSWORD:?--password required}"

# conflict: can't use both
if [[ -n "$CRED_ZIP" && "$HAVE_CREDENTIALS" == true ]]; then
  echo "❌ --credentials-zip and --have-credentials are mutually exclusive" >&2
  exit 1
fi

# ensure L4T exists, else fetch it
if [[ ! -d $L4T_DIR ]]; then
  echo "L4T directory '$L4T_DIR' not found; running get_robot_rootfs.sh..."
  if [[ -n "$ROOTFS_GID" ]]; then
    "$SCRIPT_DIR/get_robot_rootfs.sh" --rootfs-gid "$ROOTFS_GID"
  else
    "$SCRIPT_DIR/get_robot_rootfs.sh"
  fi
  if [[ ! -d $L4T_DIR ]]; then
    echo "❌ failed to obtain L4T directory at '$L4T_DIR'" >&2
    exit 1
  fi
fi

# prepare credentials
if [[ -n "$CRED_ZIP" ]]; then
  echo "Unpacking credentials from zip: $CRED_ZIP into $VPN_DIR"
  rm -rf "$VPN_DIR"
  mkdir -p "$VPN_DIR"
  unzip -o "$CRED_ZIP" -d "$VPN_DIR"
  # flatten nested folder if present
  mapfile -t entries < <(find "$VPN_DIR" -mindepth 1 -maxdepth 1)
  if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then
    echo "Found nested directory, flattening contents..."
    mv "${entries[0]}"/* "$VPN_DIR/"
    rmdir "${entries[0]}"
  fi
elif [[ "$HAVE_CREDENTIALS" == true ]]; then
  echo "Using existing credentials in $VPN_DIR"
  # you may want to verify per-robot subdirs exist here
else
  echo "Pulling credentials into: $VPN_DIR"
  ./get_robot_credentials.sh \
    --robots "$ROBOTS" \
    --password "$PASSWORD" \
    --output "$VPN_DIR"
fi

# create images per robot
IFS=',' read -ra RS <<< "$ROBOTS"
for R in "${RS[@]}"; do
  echo "=== setting up rootfs for robot $R ==="
  sudo ./setup_rootfs_with_robot_number.sh \
    --vpn-credentials "$VPN_DIR" \
    --rootfs-dir "$L4T_DIR/rootfs" \
    --robot "$R"

  echo "=== creating system images for robot $R ==="
  sudo ./generate_partition_images.sh --l4t-dir "$L4T_DIR"

  echo "=== saving system images for robot $R ==="
  sudo ./save_system_images.sh \
    --l4t-dir "$L4T_DIR" \
    --output "$IMAGES_DIR" \
    --robot "$R"
done

echo "✓ all images created under $IMAGES_DIR"

