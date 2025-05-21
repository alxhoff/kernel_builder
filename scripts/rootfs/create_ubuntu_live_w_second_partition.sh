#!/bin/bash
set -euo pipefail

ISO_URL="https://releases.ubuntu.com/20.04/ubuntu-20.04.6-desktop-amd64.iso"
ISO_NAME="ubuntu-20.04.6-desktop-amd64.iso"
LABEL="workspace"

DEVICE=""
TAR_FILE=""
ROBOT_LIST=""
PASSWORD=""


# --- Enforce root ---
if [[ "$EUID" -ne 0 ]]; then
  echo "❌ This script must be run with sudo or as root."
  exit 1
fi

show_help() {
  cat <<EOF
Usage: $0 [--device <sdX>]

This script:
  1. Downloads Ubuntu 20.04.6 ISO (if not present)
  2. Writes it to the selected USB device
  3. Creates a second ext4 partition (~32 GB) labeled "$LABEL"

Options:
  --device <sdX>   Specify target USB block device (e.g., sdb)
  --tar jp.tar.gz  Tar of jetpack sources to be used
  --robots X,Y,Z   Comma separated list of robot numbers to be flashed
  --password XXX   SSH Password used for pulling VPN credentials
  -h, --help       Show this help message

If --device is not specified, available removable devices will be listed for selection.
EOF
  exit 0
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      DEVICE="/dev/$2"
      shift 2
      ;;
    --tar)
      TAR_FILE="$2"
      shift 2
      ;;
	--robots)
	  ROBOT_LIST="$2"
	  shift 2
	  ;;
	--password)
	  PASSWORD="$2"
	  shift 2
	  ;;
    -h|--help)
      show_help
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Use --help for usage."
      exit 1
      ;;
  esac
done

if grep -qi "arch" /etc/os-release; then
  DISTRO="arch"
elif grep -qi "ubuntu" /etc/os-release; then
  DISTRO="ubuntu"
else
  DISTRO="unknown"
fi

if [[ "$DISTRO" == "ubuntu" ]]; then
   sudo apt-get update
   sudo apt-get install -y fdisk sshpass
fi

# --- Pull certs from multiple robots ---
INTERFACES=(wlan0 modem1 modem2 modem3)
REMOTE_PATH="/etc/openvpn/cartken/2.0/crt"
TMP_CERT_DIR="vpn"
mkdir -p "$TMP_CERT_DIR"
if [[ -n "$ROBOT_LIST" ]]; then
  IFS=',' read -ra ROBOTS <<< "$ROBOT_LIST"
  mkdir -p vpn

  for ROBOT in "${ROBOTS[@]}"; do
	echo "[*] Running: cartken r ip $ROBOT"
	cartken r ip "$ROBOT" || true

    echo "[*] Processing robot $ROBOT..."
    #ROBOT_IPS=$(cartken r ip "$ROBOT" 2>&1)
	ROBOT_IPS=$(timeout 5s cartken r ip "$ROBOT" 2>&1)

	if [[ $? -ne 0 ]]; then
	  echo "⚠️  cartken r ip failed or timed out for robot $ROBOT"
	  echo "$ROBOT_IPS"
	  continue
	fi

	echo "[*] IP output for robot $ROBOT:"
	echo "$ROBOT_IPS"

    ROBOT_IP=""

    while read -r iface ip _; do
      for match_iface in "${INTERFACES[@]}"; do
        if [[ "$iface" == "$match_iface" ]]; then
          echo "Testing $iface ($ip)..."
          if ping -4 -c 1 -W 2 "$ip" >/dev/null 2>&1; then
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
      echo "❌ Could not reach robot $ROBOT"
      continue
    fi

    echo "[*] Pulling certs from robot $ROBOT ($ROBOT_IP)..."
    sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "cartken@$ROBOT_IP:$REMOTE_PATH/robot.crt" "$TMP_CERT_DIR/${ROBOT}.crt"
    sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "cartken@$ROBOT_IP:$REMOTE_PATH/robot.key" "$TMP_CERT_DIR/${ROBOT}.key"
  done

  echo "[✓] All certs saved to ./vpn/"
fi

# --- Interactive device selection ---
if [[ -z "$DEVICE" ]]; then
  echo "[*] Scanning removable USB devices..."
  echo "--------------------------------------------------------"
  lsblk -dpno NAME,SIZE,MODEL,TRAN | grep -E '\susb$' || echo "No USB devices found."
  echo "--------------------------------------------------------"
  read -rp "Enter device name (e.g., /dev/sdb): " DEVICE
fi

# --- Validate device ---
if [[ ! -b "$DEVICE" ]]; then
  echo "❌ Device $DEVICE not found"
  exit 1
fi

# --- ISO download ---
if [[ ! -f "$ISO_NAME" ]]; then
  echo "[*] Downloading Ubuntu 20.04 ISO..."
  wget -c "$ISO_URL" -O "$ISO_NAME"
else
  echo "[*] Found existing ISO: $ISO_NAME"
fi

# --- Confirm wipe ---
read -rp "⚠️  About to write ISO to $DEVICE (this will erase all data). Continue? [y/N]: " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 1
fi

# --- Write ISO ---
echo "[*] Writing ISO to $DEVICE..."
dd if="$ISO_NAME" of="$DEVICE" bs=4M status=progress conv=fsync

# --- Wait for device to refresh ---
sleep 5

# --- Unmount any auto-mounted partitions ---
echo "[*] Unmounting all partitions on $DEVICE..."
for p in $(lsblk -ln -o NAME "$DEVICE" | tail -n +2); do
  umount "/dev/$p" 2>/dev/null || true
done

# --- Create 2nd partition ---
echo "[*] Creating 32GiB workspace partition at 8GiB offset using fdisk..."

START_SECTOR=16777216
END_SECTOR=$((START_SECTOR + 67108864))  # 32 GiB worth of 512-byte sectors

# Create fdisk script
FDISK_SCRIPT=$(mktemp)
cat > "$FDISK_SCRIPT" <<EOF
n
p
3
$START_SECTOR
$END_SECTOR
w
EOF

fdisk_output=$(fdisk "$DEVICE" < "$FDISK_SCRIPT" 2>&1)
rm "$FDISK_SCRIPT"

if [[ $? -ne 0 ]]; then
  echo "❌ fdisk failed:"
  echo "$fdisk_output"
  exit 1
fi

echo "[*] Partition table written. Forcing kernel to reread..."
blockdev --rereadpt "$DEVICE" || partprobe "$DEVICE"
sleep 2

PARTITION="${DEVICE}3"
if [[ ! -b "$PARTITION" ]]; then
  echo "❌ Partition $PARTITION not found after creation"
  lsblk "$DEVICE"
  exit 1
fi

echo "[*] Formatting $PARTITION as ext4 (label: workspace)..."
mkfs.ext4 -L workspace "$PARTITION"

echo "[✓] Workspace partition created and formatted."

# --- Mount workspace partition ---
MOUNT_DIR=$(mktemp -d)
EXTRACT_DIR="cartken_flash"
EXTRACT_LOC="$MOUNT_DIR/$EXTRACT_DIR"
echo "[*] Mounting workspace partition at $MOUNT_DIR..."
mount "$PARTITION" "$MOUNT_DIR"

# --- Download file from Google Drive ---
if ! command -v gdown &>/dev/null; then
  echo "[*] Installing gdown..."

  if [[ "$DISTRO" == "arch" ]]; then
	pip install --break-system-packages gdown
  else
    sudo apt-get update
    sudo apt-get install -y python3-pip curl
    pip3 install --break-system-packages --upgrade gdown || pip3 install --upgrade gdown
  fi
fi

OUTFILE="$MOUNT_DIR/cartken_flash.tar.gz"
mkdir -p "$EXTRACT_LOC"
if [[ -n "$TAR_FILE" ]]; then
  echo "[*] Using user-supplied tar file: $TAR_FILE"
  cp "$TAR_FILE" "$OUTFILE"
else
  echo "[*] Downloading file from Google Drive..."
  gdown 1-MEJNanz2eWXEhm5JC2tyiCAf8BLX_9h -O "$OUTFILE"
fi
echo "tar -xvf "$OUTFILE" -C "$EXTRACT_LOC""
tar -xvf "$OUTFILE" -C "$EXTRACT_LOC"
rm -f "$OUTFILE"

# --- Fetch script from GitHub ---
echo "[*] Downloading flash script..."
curl -fsSL \
  https://raw.githubusercontent.com/alxhoff/kernel_builder/refs/heads/master/scripts/rootfs/flash_robot_from_live_usb.sh \
  -o "$EXTRACT_LOC/cartken_flash.sh"
curl -fsSL \
  https://raw.githubusercontent.com/alxhoff/kernel_builder/refs/heads/master/scripts/rootfs/flash_jetson_ALL_sdmmc_partition_qspi.sh \
  -o "$EXTRACT_LOC/flash_jetson_ALL_sdmmc_partition_qspi.sh"
curl -fsSL \
  https://raw.githubusercontent.com/alxhoff/kernel_builder/refs/heads/master/scripts/rootfs/move_cartken_flash.sh \
  -o "$MOUNT_DIR/move_cartken_flash.sh"

chmod +x "$EXTRACT_LOC/cartken_flash.sh"
chmod +x "$EXTRACT_LOC/flash_jetson_ALL_sdmmc_partition_qspi.sh"
chmod +x "$MOUNT_DIR/move_cartken_flash.sh"

# --- Pull certs from multiple robots ---
mv "$TMP_CERT_DIR" "$EXTRACT_LOC"

# --- Finalize ---
sync
umount "$MOUNT_DIR"
rmdir "$MOUNT_DIR"
echo "[✓] Workspace populated and unmounted."

echo "[✓] Done. Bootable USB created on $DEVICE with 32GB workspace ($PARTITION)"

