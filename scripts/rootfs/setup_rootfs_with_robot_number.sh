#!/usr/bin/env bash
set -euo pipefail

# defaults
REMOTE_CRT_PATH="etc/openvpn/cartken/2.0/crt"
SSH_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINWZqz53cFupV4m8yzdveB6R8VgM17OKDuznTRaKxHIx info@cartken.com'

usage() {
  cat <<EOF
Usage: sudo $0 \
  --vpn-credentials DIR \
  --rootfs-dir DIR \
  --robot N

  --vpn-credentials  Path to folder with ROBOT.crt and .key
  --rootfs-dir       Target rootfs mount point
  --robot            Robot number (used as name suffix)
EOF
  exit 1
}

# parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --vpn-credentials)
      VPN_DIR="$2"
      shift 2
      ;;
    --rootfs-dir)
      ROOTFS="$2"
      shift 2
      ;;
    --robot)
      ROBOT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      ;;
  esac
done

: "${VPN_DIR:?--vpn-credentials required}"
: "${ROOTFS:?--rootfs-dir required}"
: "${ROBOT:?--robot required}"

if [[ $EUID -ne 0 ]]; then
  echo "❌ must be run as root"
  exit 1
fi

# 1) set hostname & /etc/hosts
NEW_HOST="cart${ROBOT}jetson"
echo "$NEW_HOST" > "$ROOTFS/etc/hostname"
if grep -q '^127\.0\.1\.1' "$ROOTFS/etc/hosts"; then
  sed -i "s/^127\.0\.1\.1.*/127.0.1.1    $NEW_HOST/" "$ROOTFS/etc/hosts"
else
  echo "127.0.1.1    $NEW_HOST" >> "$ROOTFS/etc/hosts"
fi

# 2) set CARTKEN_CART_NUMBER in /etc/environment
ENVF="$ROOTFS/etc/environment"
if grep -q '^CARTKEN_CART_NUMBER=' "$ENVF"; then
  sed -i "s/^CARTKEN_CART_NUMBER=.*/CARTKEN_CART_NUMBER=$ROBOT/" "$ENVF"
else
  echo "CARTKEN_CART_NUMBER=$ROBOT" >> "$ENVF"
fi

# 3) inject SSH key
AUTH_DIR="$ROOTFS/home/cartken/.ssh"
AUTHF="$AUTH_DIR/authorized_keys"
mkdir -p "$AUTH_DIR"
chmod 700 "$AUTH_DIR"
touch "$AUTHF"
grep -qxF "$SSH_KEY" "$AUTHF" || echo "$SSH_KEY" >> "$AUTHF"
chmod 600 "$AUTHF"
chown -R 1000:1000 "$AUTH_DIR"

# 4) copy VPN certs
DEST="$ROOTFS/$REMOTE_CRT_PATH"
mkdir -p "$DEST"
cp "$VPN_DIR/${ROBOT}.crt" "$DEST/robot.crt"
cp "$VPN_DIR/${ROBOT}.key" "$DEST/robot.key"

echo "✓ rootfs at '$ROOTFS' configured for cart${ROBOT}"

