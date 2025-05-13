#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
FILE_ID="17npAsBctuCWB7PHwYnPJXW-8GVQvMKCg"
TAR_NAME="jetson_sdmmc_qspi_bundle.tar.gz"
EXTRACT_DIR="cartken_flash"
ROOTFS_PATH="$(realpath "$EXTRACT_DIR")/Linux_for_Tegra/rootfs"
FLASH_SCRIPT="$(realpath "$EXTRACT_DIR")/flash_jetson_ALL_sdmmc_partition_qspi.sh"
REMOTE_PATH="/etc/openvpn/cartken/2.0/crt"
SSH_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINWZqz53cFupV4m8yzdveB6R8VgM17OKDuznTRaKxHIx info@cartken.com'
INTERFACES=(wlan0 modem1 modem2 modem3)

# --- Parse args ---
TAR_FILE=""
ROBOT_NUMBER=""
DRY_RUN=0

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
    --dry-run)
      DRY_RUN=1
      shift
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

# --- Download tar if not provided ---
if [[ -z "$TAR_FILE" ]]; then
  echo "Downloading bundle via gdown..."
  gdown "$FILE_ID" -O "$TAR_NAME"
  TAR_FILE="$TAR_NAME"
fi

# --- Extract ---
if [[ -d "$EXTRACT_DIR/Linux_for_Tegra" ]]; then
  echo "Skipping extraction, $EXTRACT_DIR/Linux_for_Tegra already exists."
else
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
  echo "Fetching robot IPs..."
  ROBOT_IPS=$(cartken r ip "$ROBOT_NUMBER" 2>&1)
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

  LOCAL_DEST="$ROOTFS_PATH/etc/openvpn/cartken/2.0/crt"
  mkdir -p "$LOCAL_DEST"

  echo "Copying certs from robot..."
  scp "cartken@$ROBOT_IP:$REMOTE_PATH/robot.crt" "$LOCAL_DEST/"
  scp "cartken@$ROBOT_IP:$REMOTE_PATH/robot.key" "$LOCAL_DEST/"

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

