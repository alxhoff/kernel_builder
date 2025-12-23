#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
REMOTE_PATH="/etc/openvpn/cartken/2.0/crt"
SSH_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINWZqz53cFupV4m8yzdveB6R8VgM17OKDuznTRaKxHIx info@cartken.com'
INTERFACES=(wlan0 modem1 modem2 modem3)
CERT_PATH=""
KEY_PATH=""

# --- Help function ---
show_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

This script prepares and flashes a Jetson device using a local BSP rootfs.
It can optionally pull certs and inject configuration for a specific robot.

Options:
  --target-bsp <version> Target JetPack version (e.g., 5.1.2). (Required)
  --soc <soc>            Target SoC (e.g., t234 for Orin). (Required)
  --robot-number <id>    Set robot number and fetch certs + inject hostname/env.
  --dry-run              Simulate connectivity and cert fetch without execution.
  --password             Password for pulling VPN credentials.
  --skip-vpn	    Skips pulling and updaing the VPN certificates
  --crt                  Provide the VPN certificate directly.
  --key                  Provide the VPN key directly.
  --zip                  Provide a zip file containing the VPN certificate and key.
  --l4t-dir <path>       Specify the L4T directory path. (Optional, default is derived from TARGET_BSP)
  -h, --help             Show this help message and exit.

Examples:
  $0 --target-bsp 5.1.2 --soc t234 --robot-number 302

Notes:
- This script requires a local BSP directory (e.g., 5.1.2/Linux_for_Tegra).
- This script must be run as root.
EOF
}

# --- Parse args ---
TARGET_BSP="5.1.5"
SOC="orin"
ROBOT_NUMBER=""
DRY_RUN=0
PASSWORD=""
SKIP_VPN=0
ZIP_PATH=""
L4T_DIR_ARG=""

run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[dry-run] $@"
    else
        eval "$@"
    fi
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --target-bsp)
      TARGET_BSP="$2"
      shift 2
      ;;
    --soc)
      SOC="$2"
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
	--skip-vpn)
	  SKIP_VPN=1
	  shift
	  ;;
    --password)
      PASSWORD="$2"
      shift 2
      ;;
    --crt)
      CERT_PATH="$2"
      shift 2
      ;;
    --key)
      KEY_PATH="$2"
      shift 2
      ;;
    --zip)
      ZIP_PATH="$2"
      shift 2
      ;;
    --l4t-dir)
      L4T_DIR_ARG="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"; exit 1
      ;;
  esac
done



# --- Validate required args ---
if [[ -z "${ROBOT_NUMBER-}" && -z "${CERT_PATH-}" && -z "${KEY_PATH-}" && -z "${ZIP_PATH-}" && "$SKIP_VPN" -eq 0 ]]; then
    echo "Error: Either --robot-number, --crt/--key, --zip or --skip-vpn must be provided if not skipping VPN." >&2
    show_help
    exit 1
fi
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root." >&2
    exit 1
fi

# --- Set up paths ---
SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "$L4T_DIR_ARG" ]]; then
  L4T_DIR="$L4T_DIR_ARG"
else
  L4T_DIR="$SCRIPT_DIRECTORY/$TARGET_BSP/Linux_for_Tegra"
fi
ROOTFS_PATH="$L4T_DIR/rootfs"
FLASH_SCRIPT="$L4T_DIR/flash_jetson_ALL_sdmmc_partition_qspi.sh"
CHROOT_CMD_FILE="chroot_configured_commands.txt"

# --- Check for L4T directory ---
if [[ ! -d "$L4T_DIR" ]]; then
  echo "Error: Tegra directory '$L4T_DIR' not found." >&2
  echo "Please ensure the BSP for $TARGET_BSP is correctly located." >&2
  exit 1
fi

# --- Install dependencies ---
if grep -qi "arch" /etc/os-release; then
  DISTRO="arch"
elif grep -qi "ubuntu" /etc/os-release; then
  DISTRO="ubuntu"
else
  DISTRO="unknown"
fi

if [[ "$DISTRO" == "ubuntu" ]]; then
   sudo apt-get update
   sudo apt-get install -y qemu-user-static libxml2-utils sshpass curl unzip
fi

# --- Pull certs and maybe chroot ---
if [[ -n "$ROBOT_NUMBER" ]]; then
  LOCAL_DEST="$ROOTFS_PATH/etc/openvpn/cartken/2.0/crt"
  run mkdir -p "$LOCAL_DEST"

  if [[ -n "$ZIP_PATH" ]]; then
    TEMP_DIR=$(mktemp -d)
    if [ -d "$TEMP_DIR" ]; then
        trap 'rm -rf "$TEMP_DIR"' EXIT
    else
        echo "Failed to create temp directory" >&2
        exit 1
    fi
    echo "Extracting certs from $ZIP_PATH..."
    if ! unzip -j "$ZIP_PATH" -d "$TEMP_DIR"; then
        echo "Failed to unzip $ZIP_PATH" >&2
        exit 1
    fi

    CERT_PATH=$(find "$TEMP_DIR" -name "*.crt" | head -n 1)
    KEY_PATH=$(find "$TEMP_DIR" -name "*.key" | head -n 1)

    if [[ -z "$CERT_PATH" || -z "$KEY_PATH" ]]; then
      echo "Error: .crt or .key file not found in the zip archive." >&2
      exit 1
    fi
  fi

  NEED_CERT=0
  NEED_KEY=0

  if [[ -n "$CERT_PATH" ]]; then
      echo "Copying local cert from $CERT_PATH..."
      run cp "$CERT_PATH" "$LOCAL_DEST/robot.crt"
  else
      NEED_CERT=1
  fi

  if [[ -n "$KEY_PATH" ]]; then
      echo "Copying local key from $KEY_PATH..."
      run cp "$KEY_PATH" "$LOCAL_DEST/robot.key"
  else
      NEED_KEY=1
  fi

  if [[ "$SKIP_VPN" -eq 0 && ( "$NEED_CERT" -eq 1 || "$NEED_KEY" -eq 1 ) ]]; then

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
	run sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		"cartken@$ROBOT_IP:$REMOTE_PATH/robot.crt" "$LOCAL_DEST/"
	run sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		"cartken@$ROBOT_IP:$REMOTE_PATH/robot.key" "$LOCAL_DEST/"
    else
      run scp "cartken@$ROBOT_IP:$REMOTE_PATH/robot.crt" "$LOCAL_DEST/"
      run scp "cartken@$ROBOT_IP:$REMOTE_PATH/robot.key" "$LOCAL_DEST/"
    fi
  elif [[ "$SKIP_VPN" -eq 1 && ( "$NEED_CERT" -eq 1 || "$NEED_KEY" -eq 1 ) ]]; then
      echo "Error: --key or --crt missing, and --skip-vpn prevents fallback."
      exit 1
  else
      echo "--skip-vpn active, skipping VPN certificate copy."
  fi
  
  echo "Running chroot..."
  touch "$CHROOT_CMD_FILE"
  run sudo "$L4T_DIR/jetson_chroot.sh" "$ROOTFS_PATH" "$SOC" "$CHROOT_CMD_FILE"

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

read -rp "✅ Rootfs at $L4T_DIR is ready for flashing. Please put the robot in recovery mode and press [Enter] to continue..."

if [ -f "$L4T_DIR/tools/l4t_flash_prerequisites.sh" ]; then
  echo "Running l4t_flash_prerequisites.sh..."
  (cd "$L4T_DIR" && ./tools/l4t_flash_prerequisites.sh)
fi

# --- Flash ---
echo "Running flash script: $FLASH_SCRIPT"
curl -fsSL \
https://raw.githubusercontent.com/alxhoff/kernel_builder/refs/heads/master/scripts/rootfs/flash_jetson_ALL_sdmmc_partition_qspi.sh \
-o "$FLASH_SCRIPT"
chmod +x "$FLASH_SCRIPT"

MAJOR_VERSION=$(echo "$TARGET_BSP" | cut -d. -f1)

if [[ "$MAJOR_VERSION" -ge 6 ]]; then
  DTB_FILE="$L4T_DIR/kernel/dtb/tegra234-p3737-0000+p3701-0000.dtb"
  echo "Jetpack 6.0+ detected, using DTB file: $DTB_FILE"
  "$FLASH_SCRIPT" --l4t-dir "$L4T_DIR" --dtb-file "$DTB_FILE"
else
  "$FLASH_SCRIPT" --l4t-dir "$L4T_DIR"
fi