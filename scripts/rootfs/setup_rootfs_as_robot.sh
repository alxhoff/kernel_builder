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
  --help                    Show this help message
EOF
}

ROBOT_NUMBER=""
SOC=""
TAG=""
TARGET_BSP=""
BASE_BSP=""
DRY_RUN=0

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
BASE_BSP_ROOT="$SCRIPT_DIRECTORY/$BASE_BSP/Linux_for_Tegra"
TARGET_BSP_ROOT="$TEGRA_DIR"
L4T_DIR="$TEGRA_DIR"
OTA_DIR="$SCRIPT_DIRECTORY/ota_update"
ROOTFS="$TEGRA_DIR/rootfs"
CHROOT_CMD_FILE="chroot_configured_commands.txt"

if [[ ! -d "$TEGRA_DIR" ]]; then
    echo "Error: Tegra directory '$TEGRA_DIR' does not exist."
    exit 1
fi

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
            elif ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
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
LOCAL_DEST="$ROOTFS/etc/openvpn/cartken/2.0/crt"
run mkdir -p "$LOCAL_DEST"

echo "Copying certs from robot (will overwrite existing files)..."
run scp "cartken@$ROBOT_IP:$REMOTE_PATH/robot.crt" "$LOCAL_DEST/"
run scp "cartken@$ROBOT_IP:$REMOTE_PATH/robot.key" "$LOCAL_DEST/"

echo "Checksums after copy:"
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] sha256sum $LOCAL_DEST/robot.crt $LOCAL_DEST/robot.key"
else
    sha256sum "$LOCAL_DEST/robot.crt" "$LOCAL_DEST/robot.key"
fi

echo "Running chroot..."
run sudo "$TEGRA_DIR/jetson_chroot.sh" "$TEGRA_DIR/rootfs" "$SOC" "$CHROOT_CMD_FILE"

echo "Creating OTA payload (docker)..."
run "$OTA_DIR/create_ota_payload_docker.sh" \
    --base-bsp "$BASE_BSP_ROOT" \
    --target-bsp "$TARGET_BSP_ROOT"

echo "Extracting kernel version..."
KERNEL_VERSION=$(strings "$L4T_DIR/kernel/Image" | grep -oP "Linux version \K[0-9.-]+-[^ ]+")

echo "Building OTA update package..."
run "$OTA_DIR/create_debian.sh" \
    --otapayload "$L4T_DIR/bootloader/jetson-agx-orin-devkit/ota_payload_package.tar.gz" \
    --kernel-version "$KERNEL_VERSION" \
    --repo-version "$TAG" \
    --target-bsp="$TARGET_BSP" \
    --base-bsp="$BASE_BSP" \
    --extlinux-conf "$L4T_DIR/rootfs/boot/extlinux/extlinux.conf"

echo "Done."

