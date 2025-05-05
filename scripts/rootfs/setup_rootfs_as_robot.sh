#!/bin/bash
set -euo pipefail

print_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --robot-number NUM        Robot number to fetch certificates from
  --soc SOC                 SOC name for jetson_chroot.sh
  --tag TAG                 Repo version tag
  --target-bsp VERSION      Target JetPack version (also used to locate Linux_for_Tegra)
  --base-bsp VERSION        Base JetPack version
  --dry-run                 Print commands instead of executing
  --skip-vpn			    Skips pulling and updaing the VPN certificates
  --help                    Show this help message
EOF
}

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root due to rootfs permissions."
    exit 1
fi

ROBOT_NUMBER=""
SOC=""
TAG=""
TARGET_BSP=""
BASE_BSP=""
DRY_RUN=0
SKIP_VPN=0
CERT_PATH=""
KEY_PATH=""

run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[dry-run] $*"
    else
        eval "$@"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --robot-number) ROBOT_NUMBER="$2"; shift 2 ;;
        --robot-number=*) ROBOT_NUMBER="${1#*=}"; shift ;;
        --soc) SOC="$2"; shift 2 ;;
        --soc=*) SOC="${1#*=}"; shift ;;
        --tag) TAG="$2"; shift 2 ;;
        --tag=*) TAG="${1#*=}"; shift ;;
        --target-bsp) TARGET_BSP="$2"; shift 2 ;;
        --target-bsp=*) TARGET_BSP="${1#*=}"; shift ;;
        --base-bsp) BASE_BSP="$2"; shift 2 ;;
        --base-bsp=*) BASE_BSP="${1#*=}"; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
		--skip-vpn) SKIP_VPN=1; shift ;;
		--cert) CERT_PATH="$2"; shift 2 ;;
		--cert=*) CERT_PATH="${1#*=}"; shift ;;
		--key) KEY_PATH="$2"; shift 2 ;;
		--key=*) KEY_PATH="${1#*=}"; shift ;;
        --help) print_help; exit 0 ;;
        *) echo "Unknown argument: $1"; print_help; exit 1 ;;
    esac
done

if [[ -z "$ROBOT_NUMBER" || -z "$SOC" || -z "$TAG" || -z "$TARGET_BSP" || -z "$BASE_BSP" ]]; then
    echo "Error: Missing required arguments."
    print_help
    exit 1
fi

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEGRA_DIR="$SCRIPT_DIRECTORY/$TARGET_BSP/Linux_for_Tegra"
L4T_DIR="$TEGRA_DIR"
OTA_DIR="$SCRIPT_DIRECTORY/ota_update"
ROOTFS="$TEGRA_DIR/rootfs"
CHROOT_CMD_FILE="chroot_configured_commands.txt"

ROBOT_SUFFIX=$(printf "cart%03d" "$ROBOT_NUMBER")
NEW_HOSTNAME="${ROBOT_SUFFIX}jetson"

if [[ ! -d "$TEGRA_DIR" ]]; then
    echo "Error: Tegra directory '$TEGRA_DIR' does not exist."
    exit 1
fi

echo "Guarenteeing that DTBs are available"
ROOTFS_BOOT_DIR="$ROOTFS/boot"
ROOTFS_BOOT_DTB_DIR="$ROOTFS_BOOT_DIR/dtb"
DTB_NAMES=("tegra234-p3701-0000-p3737-0000.dtb" "tegra234-p3701-0005-p3737-0000.dtb")
L4T_KERNEL_DTB_DIR="$L4T_DIR/kernel/dtb"

for DTB_NAME in "${DTB_NAMES[@]}"; do
	SOURCE_DTB_FILE="$ROOTFS_BOOT_DTB_DIR/$DTB_NAME"
	TARGET_DTB_FILE="$L4T_KERNEL_DTB_DIR/$DTB_NAME"

	if [[ -f "$SOURCE_DTB_FILE" ]]; then
		cp "$SOURCE_DTB_FILE" "$TARGET_DTB_FILE"
	else
		echo "Warning: DTB $SOURCE_DTB_FILE not found!"
	fi
done

LOCAL_DEST="$ROOTFS/etc/openvpn/cartken/2.0/crt"
run mkdir -p "$LOCAL_DEST"

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
	ROBOT_IPS=$(cartken r ip "$ROBOT_NUMBER" 2>&1)

	INTERFACES=(wlan0 modem1 modem2 modem3)
	ROBOT_IP=""

	echo "Trying to select a reachable IP from:"
	echo "$ROBOT_IPS"

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

	REMOTE_PATH="/etc/openvpn/cartken/2.0/crt"

	echo "Copying certs from robot (will overwrite existing files)..."
	run scp "cartken@$ROBOT_IP:$REMOTE_PATH/robot.crt" "$LOCAL_DEST/"
	run scp "cartken@$ROBOT_IP:$REMOTE_PATH/robot.key" "$LOCAL_DEST/"

	echo "Checksums after copy:"
	if [[ "$DRY_RUN" -eq 1 ]]; then
		echo "[dry-run] sha256sum $LOCAL_DEST/robot.crt $LOCAL_DEST/robot.key"
	else
		sha256sum "$LOCAL_DEST/robot.crt" "$LOCAL_DEST/robot.key"
	fi
elif [[ "$SKIP_VPN" -eq 1 && ( "$NEED_CERT" -eq 1 || "$NEED_KEY" -eq 1 ) ]]; then
    echo "Error: --key or --cert missing, and --skip-vpn prevents fallback."
    exit 1
else
    echo "--skip-vpn active, skipping VPN certificate copy."
fi


echo "Running chroot..."
run sudo "$TEGRA_DIR/jetson_chroot.sh" "$TEGRA_DIR/rootfs" "$SOC" "$CHROOT_CMD_FILE"

echo "Setting hostname inside rootfs to: $NEW_HOSTNAME"
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] echo \"$NEW_HOSTNAME\" > \"$ROOTFS/etc/hostname\""
else
    echo "$NEW_HOSTNAME" > "$ROOTFS/etc/hostname"
fi

if grep -q "^127\.0\.1\.1" "$ROOTFS/etc/hosts"; then
	if [[ "$DRY_RUN" -eq 1 ]]; then
		echo "[dry-run] sed -i \"s/^127\\.0\\.1\\.1.*/127.0.1.1    $NEW_HOSTNAME/\" \"$ROOTFS/etc/hosts\""
	else
		sed -i "s/^127\.0\.1\.1.*/127.0.1.1    $NEW_HOSTNAME/" "$ROOTFS/etc/hosts"
	fi
else
    echo "127.0.1.1    $NEW_HOSTNAME" >> "$ROOTFS/etc/hosts"
fi

echo "Setting CARTKEN_CART_NUMBER=$ROBOT_NUMBER in /etc/environment"

if grep -q "^CARTKEN_CART_NUMBER=" "$ROOTFS/etc/environment"; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[dry-run] sed -i \"s/^CARTKEN_CART_NUMBER=.*/CARTKEN_CART_NUMBER=$ROBOT_NUMBER/\" \"$ROOTFS/etc/environment\""
    else
        sed -i "s/^CARTKEN_CART_NUMBER=.*/CARTKEN_CART_NUMBER=$ROBOT_NUMBER/" "$ROOTFS/etc/environment"
    fi
else
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[dry-run] echo \"CARTKEN_CART_NUMBER=$ROBOT_NUMBER\" >> \"$ROOTFS/etc/environment\""
    else
        echo "CARTKEN_CART_NUMBER=$ROBOT_NUMBER" >> "$ROOTFS/etc/environment"
    fi
fi

HOTSPOT_FILE="$ROOTFS/etc/NetworkManager/system-connections/Hotspot.nmconnection"

if [[ -f "$HOTSPOT_FILE" ]]; then
    echo "Setting Hotspot SSID to $NEW_HOSTNAME in $HOTSPOT_FILE"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[dry-run] sed -i \"s/^ssid=.*/ssid=$NEW_HOSTNAME/\" \"$HOTSPOT_FILE\""
    else
        sed -i "s/^ssid=.*/ssid=$NEW_HOSTNAME/" "$HOTSPOT_FILE"
    fi
else
    echo "Warning: Hotspot configuration file not found: $HOTSPOT_FILE"
fi

SSH_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINWZqz53cFupV4m8yzdveB6R8VgM17OKDuznTRaKxHIx info@cartken.com'
AUTH_KEYS_PATH="$ROOTFS/home/cartken/.ssh/authorized_keys"

echo "Injecting SSH key into $AUTH_KEYS_PATH"
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] mkdir -p \"$(dirname "$AUTH_KEYS_PATH")\""
    echo "[dry-run] chmod 700 \"$(dirname "$AUTH_KEYS_PATH")\""
    echo "[dry-run] echo \"$SSH_KEY\" >> \"$AUTH_KEYS_PATH\""
    echo "[dry-run] chmod 600 \"$AUTH_KEYS_PATH\""
else
    mkdir -p "$(dirname "$AUTH_KEYS_PATH")"
    chmod 700 "$(dirname "$AUTH_KEYS_PATH")"
    touch "$AUTH_KEYS_PATH"
    grep -qxF "$SSH_KEY" "$AUTH_KEYS_PATH" || echo "$SSH_KEY" >> "$AUTH_KEYS_PATH"
    chmod 600 "$AUTH_KEYS_PATH"
	chown -R 1000:1000 "$(dirname "$AUTH_KEYS_PATH")"
fi

echo "Creating OTA payload (docker)..."
run "$OTA_DIR/create_ota_payload_docker.sh" \
    --base-bsp "$SCRIPT_DIRECTORY/$BASE_BSP" \
    --target-bsp "$SCRIPT_DIRECTORY/$TARGET_BSP"

echo "Extracting kernel version..."
KERNEL_VERSION=$(strings "$L4T_DIR/kernel/Image" | grep -oP "Linux version \K[0-9.-]+-[^ ]+")

echo "Building OTA update package..."
run "$OTA_DIR/create_debian.sh" \
    --otapayload "$L4T_DIR/bootloader/jetson-agx-orin-devkit/ota_payload_package.tar.gz" \
    --kernel-version "$KERNEL_VERSION" \
    --repo-version "$TAG" \
    --target-bsp "$TARGET_BSP" \
    --base-bsp "$BASE_BSP" \
    --extlinux-conf "$L4T_DIR/rootfs/boot/extlinux/extlinux.conf" \
	--package-suffix "$ROBOT_SUFFIX"

echo "Done."

