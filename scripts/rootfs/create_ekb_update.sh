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
if [[ ! -f "$PAYLOAD" ]]; then
    echo "Error: Payload not found at $PAYLOAD"
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

cp "$PAYLOAD" "$DEB_DIR/opt/ota_package/bl_only_payload"

cat > "$DEB_DIR/opt/ota_package/install_payload.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

UPDATE_ENGINE="/usr/sbin/nv_update_engine"

echo "[*] Installing BUP payload to current slot..."

if [[ ! -x "$UPDATE_ENGINE" ]]; then
    echo "[*] Making nv_update_engine executable..."
    chmod +x "$UPDATE_ENGINE"
fi

"$UPDATE_ENGINE" --payload /opt/ota_package/bl_only_payload
EOF

chmod +x "$DEB_DIR/opt/ota_package/install_payload.sh"

cat > "$DEB_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/bash
set -e

echo "[*] Installing to current slot immediately..."
bash /opt/ota_package/install_payload.sh
EOF

chmod +x "$DEB_DIR/DEBIAN/postinst"

OUTPUT_DEB="$SCRIPT_DIR/jetson-${L4T_VERSION}-ekb-update.deb"
dpkg-deb --build "$DEB_DIR" "$OUTPUT_DEB"
echo "[*] Debian package created at $OUTPUT_DEB"

