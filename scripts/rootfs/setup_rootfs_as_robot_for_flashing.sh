#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
FILE_ID="1-MEJNanz2eWXEhm5JC2tyiCAf8BLX_9h"
TAR_NAME="cartken_flash.tar.gz"
EXTRACT_DIR="cartken_flash"
EXTRACT_DIR="$(realpath "$EXTRACT_DIR")"
ROOTFS_PATH="$EXTRACT_DIR/Linux_for_Tegra/rootfs"
FLASH_SCRIPT="$EXTRACT_DIR/flash_jetson_ALL_sdmmc_partition_qspi.sh"
L4T_DIR="$EXTRACT_DIR/Linux_for_Tegra"
REMOTE_PATH="/etc/openvpn/cartken/2.0/crt"
SSH_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINWZqz53cFupV4m8yzdveB6R8VgM17OKDuznTRaKxHIx info@cartken.com'
INTERFACES=(wlan0 modem1 modem2 modem3)
CERT_PATH=""
KEY_PATH=""

# --- Help function ---
show_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

This script prepares and flashes a Jetson device with a Cartken rootfs image.
It can optionally pull certs and inject configuration for a specific robot.

Options:
  --tar <path>           Use a local tarball instead of downloading via gdown.
  --robot-number <id>    Set robot number and fetch certs + inject hostname/env.
  --dry-run              Simulate connectivity and cert fetch without execution.
  --password             Password for pulling VPN credentials
  --cert                    Provide the VPN certificate directly
  --key                     Provide the VPN key directly
  -h, --help             Show this help message and exit.

Examples:
  $0 --robot-number 302
  $0 --tar my_flash_bundle.tar.gz --robot-number 315
  $0 --dry-run --robot-number 123

Notes:
- If --tar is not provided, a default tarball will be downloaded via gdown.
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
DRY_RUN=0
PASSWORD=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --tar)
      TAR_FILE="$2"
      shift 2
      ;;
    --robot-number)
      ROBOT_NUMBER="$2"
      shift 2
      ;;
	-h|--help)
      show_help
      exit 0
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
	--password)
	  PASSWORD="$2"
	  shift 2
	  ;;
	--cert)
      CERT_PATH="$2"
      shift 2
      ;;
    --key)
      KEY_PATH="$2"
      shift 2
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

if grep -qi "arch" /etc/os-release; then
  DISTRO="arch"
elif grep -qi "ubuntu" /etc/os-release; then
  DISTRO="ubuntu"
else
  DISTRO="unknown"
fi

if [[ "$DISTRO" == "ubuntu" ]]; then
   sudo apt-get update
   sudo apt-get install -y libxml2-utils sshpass
fi

# --- Extract ---
if [[ -d "$L4T_DIR" ]]; then
  echo "Skipping extraction, $L4T_DIR already exists."
else
	# --- Download tar if not provided ---
	if [[ -z "$TAR_FILE" ]]; then
	  echo "Downloading bundle via gdown.."
	  apt update
	  apt install -y python3-pip
	  PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
	  if python3 -c 'import sys; exit(0) if (sys.version_info.major, sys.version_info.minor) >= (3, 10) else exit(1)'; then
		  pip install --break-system-packages --upgrade gdown
	  else
		  pip install --upgrade gdown
	  fi
	  gdown "$FILE_ID" -O "$TAR_NAME"
	  TAR_FILE="$TAR_NAME"
	fi
  echo "Extracting archive: $TAR_FILE to $EXTRACT_DIR..."
  mkdir -p "$EXTRACT_DIR"
  if tar -xvzf "$TAR_FILE" -C "$EXTRACT_DIR"; then
    echo "Extraction (gzip) completed."
  else
    echo "Gzip extraction failed, trying plain tar..."
    tar -xvf "$TAR_FILE" -C "$EXTRACT_DIR"
    echo "Fallback extraction completed."
  fi
fi
cd "$EXTRACT_DIR"

# --- Pull certs ---
if [[ -n "$ROBOT_NUMBER" ]]; then
  LOCAL_DEST="$ROOTFS_PATH/etc/openvpn/cartken/2.0/crt"
  mkdir -p "$LOCAL_DEST"

  if [[ -n "$CERT_PATH" && -n "$KEY_PATH" ]]; then
    echo "Using provided cert and key."
    cp "$CERT_PATH" "$LOCAL_DEST/robot.crt"
    cp "$KEY_PATH" "$LOCAL_DEST/robot.key"
  else
    echo "Fetching robot IPs..."
    ROBOT_IPS=$(sudo -u "$SUDO_USER" bash -c "cartken r ip \"$ROBOT_NUMBER\" 2>&1")
    echo "$ROBOT_IPS"
    ROBOT_IP=""

    while read -r iface ip _; do
      for match_iface in "${INTERFACES[@]}"; do
        if [[ "$iface" == "$match_iface" ]]; then
          echo "Testing $iface ($ip)..."
          if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "[dry-run] Would ping $ip"
            ROBOT_IP="$ip"
            break 2
          elif ping -4 -c 1 -W 2 "$ip" >/dev/null 2>&1; then
            echo "Selected $iface ($ip) as reachable."
            ROBOT_IP="$ip"
            break 2
          else
            echo "$iface ($ip) not reachable, trying next..."
          fi
        fi
      done
    done <<< "$ROBOT_IPS"

    if [[ -z "$ROBOT_IP" ]]; then
      echo "Failed to find a reachable IP for robot $ROBOT_NUMBER"
      exit 1
    fi

    echo "Copying certs from robot..."
    if [[ -n "$PASSWORD" ]]; then
      sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "cartken@$ROBOT_IP:$REMOTE_PATH/robot.crt" "$LOCAL_DEST/"
      sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "cartken@$ROBOT_IP:$REMOTE_PATH/robot.key" "$LOCAL_DEST/"
    else
      scp "cartken@$ROBOT_IP:$REMOTE_PATH/robot.crt" "$LOCAL_DEST/"
      scp "cartken@$ROBOT_IP:$REMOTE_PATH/robot.key" "$LOCAL_DEST/"
    fi
  fi

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

read -rp "✅ Rootfs is ready for flashing. Please put the robot in recovery mode and press [Enter] to continue..."

# --- Flash ---
echo "Running flash script: $FLASH_SCRIPT"
curl -fsSL \
https://raw.githubusercontent.com/alxhoff/kernel_builder/refs/heads/master/scripts/rootfs/flash_jetson_ALL_sdmmc_partition_qspi.sh \
-o "$FLASH_SCRIPT"
chmod +x "$FLASH_SCRIPT"
"$FLASH_SCRIPT" --l4t-dir "$(realpath "$L4T_DIR")"

