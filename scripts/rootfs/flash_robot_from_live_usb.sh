#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
FILE_ID="1-MEJNanz2eWXEhm5JC2tyiCAf8BLX_9h"
TAR_NAME="cartken_flash.tar.gz"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLASH_SCRIPT="$SCRIPT_DIR/flash_jetson_ALL_sdmmc_partition_qspi.sh"
ROOTFS_PATH="$SCRIPT_DIR/Linux_for_Tegra/rootfs"
SSH_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINWZqz53cFupV4m8yzdveB6R8VgM17OKDuznTRaKxHIx info@cartken.com'

# --- Help function ---
show_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

This script prepares and flashes a Jetson device with a Cartken rootfs image.
It can optionally pull certs and inject configuration for a specific robot.

Options:
  --robot-number <id>    Set robot number and fetch certs + inject hostname/env.
  -h, --help             Show this help message and exit.

Examples:
  $0 --robot-number 302

Notes:
- This script must be run as root.
EOF
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_help
  exit 0
fi

# --- Parse args ---
TAR_FILE=""
ROBOT_NUMBER=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --robot-number)
      ROBOT_NUMBER="$2"
      shift 2
      ;;
	-h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1"; exit 1
      ;;
  esac
done

# --- Check for sudo ---
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root." >&2
    exit 1
fi

apt-add-repository universe
apt update
apt install -y libxml2-utils binutils minicom openssh-server
ln -sf /usr/bin/python3 /usr/bin/python

if id "ubuntu" &>/dev/null; then
  echo "ubuntu:cartken1" | sudo chpasswd
fi

# --- Pull certs ---
if [[ -n "$ROBOT_NUMBER" ]]; then
	CERT_SOURCE_DIR="$(dirname "$(realpath "$0")")/vpn"
	LOCAL_DEST="$ROOTFS_PATH/etc/openvpn/cartken/2.0/crt"
	mkdir -p "$LOCAL_DEST"

	CERT_CRT="$CERT_SOURCE_DIR/${ROBOT_NUMBER}.crt"
	CERT_KEY="$CERT_SOURCE_DIR/${ROBOT_NUMBER}.key"

	if [[ ! -f "$CERT_CRT" || ! -f "$CERT_KEY" ]]; then
	  echo "❌ VPN certificate or key not found for robot $ROBOT_NUMBER in vpn/ directory."
	  echo "Expected files: $CERT_CRT and $CERT_KEY"
	  exit 1
	fi

	echo "Copying VPN certs for robot $ROBOT_NUMBER from $CERT_SOURCE_DIR to $LOCAL_DEST..."
	cp "$CERT_CRT" "$LOCAL_DEST/robot.crt"
	cp "$CERT_KEY" "$LOCAL_DEST/robot.key"

  # --- Set hostname and env ---
  NEW_HOSTNAME="cart${ROBOT_NUMBER}jetson"
  echo "Setting hostname to $NEW_HOSTNAME in $ROOTFS_PATH/etc/hostname"
  echo "$NEW_HOSTNAME" > "$ROOTFS_PATH/etc/hostname"

  echo "Updating /etc/hosts to reflect new hostname"
  if grep -q "^127\.0\.1\.1" "$ROOTFS_PATH/etc/hosts"; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1    $NEW_HOSTNAME/" "$ROOTFS_PATH/etc/hosts"
  else
    echo "127.0.1.1    $NEW_HOSTNAME" >> "$ROOTFS_PATH/etc/hosts"
  fi

  echo "Writing CARTKEN_CART_NUMBER=$ROBOT_NUMBER to /etc/environment"
  if grep -q "^CARTKEN_CART_NUMBER=" "$ROOTFS_PATH/etc/environment"; then
    sed -i "s/^CARTKEN_CART_NUMBER=.*/CARTKEN_CART_NUMBER=$ROBOT_NUMBER/" "$ROOTFS_PATH/etc/environment"
  else
    echo "CARTKEN_CART_NUMBER=$ROBOT_NUMBER" >> "$ROOTFS_PATH/etc/environment"
  fi

  echo "Injecting SSH key into $ROOTFS_PATH/home/cartken/.ssh/authorized_keys"
  # --- Inject SSH key ---
  AUTH_KEYS_PATH="$ROOTFS_PATH/home/cartken/.ssh/authorized_keys"
  mkdir -p "$(dirname "$AUTH_KEYS_PATH")"
  chmod 700 "$(dirname "$AUTH_KEYS_PATH")"
  touch "$AUTH_KEYS_PATH"
  grep -qxF "$SSH_KEY" "$AUTH_KEYS_PATH" || echo "$SSH_KEY" >> "$AUTH_KEYS_PATH"
  chmod 600 "$AUTH_KEYS_PATH"
  chown -R 1000:1000 "$(dirname "$AUTH_KEYS_PATH")"
fi

# --- Flash ---
echo "Running flash script: $FLASH_SCRIPT"
if [[ -x "$FLASH_SCRIPT" ]]; then
  "$FLASH_SCRIPT"
else
  echo "Error: flash script not found or not executable at $FLASH_SCRIPT"
  exit 1
fi

