#!/usr/bin/env bash

set -euo pipefail

show_help() {
    echo "Usage: $0 --l4t-version <version>"
    echo "Options:"
    echo "  --l4t-version <version>   JetPack version, e.g., 5.1.5"
    echo "  --help                    Show this help message"
    exit 0
}

L4T_VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --l4t-version)
            shift
            L4T_VERSION="$1"
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
    shift
done

if [[ -z "$L4T_VERSION" ]]; then
    echo "Error: --l4t-version is required"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
L4T_DIR="$L4T_VERSION/Linux_for_Tegra"
ABS_L4T_DIR="$(realpath "$L4T_DIR")"
cd "$ABS_L4T_DIR"
echo "[*] Generating BUP payload..."
BOARDID=3701 FAB=000 BOARDSKU=0004 ./build_l4t_bup.sh jetson-agx-orin-devkit mmcblk0p1

PAYLOAD="$ABS_L4T_DIR/bootloader/payloads_t23x/bl_only_payload"
CAPSULE="$ABS_L4T_DIR/TEGRA_BL.Cap"

if [[ ! -f "$CAPSULE" ]]; then
    echo "[*] Generating capsule image..."
    ./generate_capsule/l4t_generate_soc_capsule.sh -i "$PAYLOAD" -o "$CAPSULE" t234
fi

if [[ ! -f "$CAPSULE" ]]; then
    echo "Error: Capsule generation failed"
    exit 1
fi

DEB_DIR="$ABS_L4T_DIR/deb_pkg"
mkdir -p "$DEB_DIR/DEBIAN" "$DEB_DIR/opt/ota_package"

cat > "$DEB_DIR/DEBIAN/control" <<EOF
Package: jetson-${L4T_VERSION}-ekb-update
Version: 1.0
Section: base
Priority: optional
Architecture: arm64
Maintainer: Auto Generated
Description: OTA Update Payload for Jetson ${L4T_VERSION} with EKB
EOF

cp "$CAPSULE" "$DEB_DIR/opt/ota_package/TEGRA_BL.Cap"

cat > "$DEB_DIR/opt/ota_package/install_payload.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

ESP_DIR="/opt/nvidia/esp"

# Function to unmount the ESP directory
unmount_esp() {
    if mountpoint -q "$ESP_DIR"; then
        echo "[*] Unmounting ESP partition..."
        umount "$ESP_DIR"
    fi
}

# Set a trap to unmount on exit
trap unmount_esp EXIT

echo "[*] Starting EKB update installation..."

CAPSULE_PATH="/opt/ota_package/TEGRA_BL.Cap"
UPDATE_DIR="EFI/UpdateCapsule"

echo "[*] Creating ESP directory at $ESP_DIR"
mkdir -p "$ESP_DIR"

echo "[*] Finding ESP partition..."
esp_uuid=$(lsblk -o name,partlabel,uuid | grep "esp" | awk '{print $3}')
if [[ -z "$esp_uuid" ]]; then
    echo "Error: ESP partition not found."
    exit 1
fi
echo "[*] Found ESP partition with UUID: $esp_uuid"

echo "[*] Mounting ESP partition..."
if mountpoint -q "$ESP_DIR"; then
    echo "[*] ESP partition already mounted at $ESP_DIR."
else
    mount UUID=$esp_uuid "$ESP_DIR"
    echo "[*] Mounted ESP partition at $ESP_DIR."
fi

echo "[*] Creating update directory at $ESP_DIR/$UPDATE_DIR"
mkdir -p "$ESP_DIR/$UPDATE_DIR"

echo "[*] Copying capsule from $CAPSULE_PATH to $ESP_DIR/$UPDATE_DIR/"
cp "$CAPSULE_PATH" "$ESP_DIR/$UPDATE_DIR/"
sync
echo "[*] Capsule copied successfully."

echo "[*] Setting UEFI OsIndications to trigger capsule update on reboot..."
printf "\x07\x00\x00\x00\x04\x00\x00\x00\x00\x00\x00\x00" > /tmp/var_tmp.bin
dd if=/tmp/var_tmp.bin of=/sys/firmware/efi/efivars/OsIndications-8be4df61-93ca-11d2-aa0d-00e098032b8c bs=12 >/dev/null 2>&1
rm /tmp/var_tmp.bin
echo "[*] UEFI OsIndications set."

echo "[*] Verifying UEFI OsIndications..."
actual_hex=$(dd if=/sys/firmware/efi/efivars/OsIndications-8be4df61-93ca-11d2-aa0d-00e098032b8c bs=12 2>/dev/null | xxd -p -c 24)
expected_hex="070000000400000000000000"

echo "Expected value (hex): $expected_hex"
echo "Actual value (hex):   $actual_hex"

if [ "$expected_hex" == "$actual_hex" ]; then
    echo "[*] UEFI OsIndications successfully verified."
else
    echo "Error: UEFI OsIndications verification failed."
    exit 1
fi

echo "[*] EKB update installation complete. Please reboot for the update to take effect."
EOF

chmod +x "$DEB_DIR/opt/ota_package/install_payload.sh"

cat > "$DEB_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/bash
set -e

echo "[*] Installing capsule update to current slot..."
bash /opt/ota_package/install_payload.sh
echo "[*] Successfully installed capsule update."
EOF

chmod +x "$DEB_DIR/DEBIAN/postinst"

OUTPUT_DEB="$SCRIPT_DIR/jetson-${L4T_VERSION}-ekb-update.deb"
dpkg-deb --build "$DEB_DIR" "$OUTPUT_DEB"
echo "[*] Debian package created at $OUTPUT_DEB"

