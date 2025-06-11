#!/usr/bin/env bash
set -euo pipefail

# defaults
default_rootfs_dir="cartken_flash/Linux_for_Tegra/rootfs"
default_vpn_dir="robot_credentials"
# default SSH public key to inject
default_ssh_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINWZqz53cFupV4m8yzdveB6R8VgM17OKDuznTRaKxHIx info@cartken.com'

REMOTE_CRT_PATH="/etc/openvpn/cartken/2.0/crt"

# usage message
usage() {
  cat <<EOF
Usage: sudo $0 \
  --robot N \
  [--rootfs-dir DIR] \
  [--vpn-credentials DIR] \
  [--ssh-key "KEY"]

  --robot               Robot number (required)
  --rootfs-dir          Path to rootfs (default: $default_rootfs_dir)
  --vpn-credentials     Path to credentials dir (default: $default_vpn_dir)
  --ssh-key             SSH public key to inject (default: built-in)
EOF
  exit 1
}

# set defaults
ROOTFS_DIR="$default_rootfs_dir"
VPN_DIR="$default_vpn_dir"
SSH_KEY="$default_ssh_key"

# parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --robot)
      ROBOT="$2"; shift 2;;
    --rootfs-dir)
      ROOTFS_DIR="$2"; shift 2;;
    --vpn-credentials)
      VPN_DIR="$2"; shift 2;;
    --ssh-key)
      SSH_KEY="$2"; shift 2;;
    -h|--help)
      usage;;
    *)
      echo "Unknown arg: $1" >&2; usage;;
  esac
done

# require mandatory args
: "${ROBOT:?--robot required}"

# must run as root
if [[ $EUID -ne 0 ]]; then
  echo "❌ must be run as root" >&2
  exit 1
fi

# 1) set hostname
NEW_HOSTNAME="cart${ROBOT}jetson"
echo "$NEW_HOSTNAME" > "$ROOTFS_DIR/etc/hostname"
if grep -q '^127\\.0\\.1\\.1' "$ROOTFS_DIR/etc/hosts"; then
  sed -i "s/^127\\.0\\.1\\.1.*/127.0.1.1    $NEW_HOSTNAME/" "$ROOTFS_DIR/etc/hosts"
else
  echo "127.0.1.1    $NEW_HOSTNAME" >> "$ROOTFS_DIR/etc/hosts"
fi

# 2) set CARTKEN_CART_NUMBER
env_file="$ROOTFS_DIR/etc/environment"
if grep -q '^CARTKEN_CART_NUMBER=' "$env_file"; then
  sed -i "s/^CARTKEN_CART_NUMBER=.*/CARTKEN_CART_NUMBER=$ROBOT/" "$env_file"
else
  echo "CARTKEN_CART_NUMBER=$ROBOT" >> "$env_file"
fi

# 3) inject SSH key
auth_dir="$ROOTFS_DIR/home/cartken/.ssh"
auth_file="$auth_dir/authorized_keys"
mkdir -p "$auth_dir"
chmod 700 "$auth_dir"
touch "$auth_file"
grep -qxF "$SSH_KEY" "$auth_file" || echo "$SSH_KEY" >> "$auth_file"
chmod 600 "$auth_file"
chown -R 1000:1000 "$auth_dir"

# 4) copy VPN certs
src_cert="$VPN_DIR/$ROBOT/robot.cert"
src_key="$VPN_DIR/$ROBOT/robot.key"
dest_dir="$ROOTFS_DIR$REMOTE_CRT_PATH"
mkdir -p "$dest_dir"
cp -- "$src_cert" "$dest_dir/robot.crt"
cp -- "$src_key"  "$dest_dir/robot.key"

echo "✓ rootfs at '$ROOTFS_DIR' configured for cart${ROBOT}"

