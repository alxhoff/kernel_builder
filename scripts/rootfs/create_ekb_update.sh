#!/usr/bin/env bash

set -euo pipefail

show_help() {
    echo "Usage: $0 --l4t-dir <path> [--both-slots]"
    echo "Options:"
    echo "  --l4t-dir <path>     Path to L4T directory containing build_l4t_bup.sh"
    echo "  --both-slots         Generate and install update for both slots (A/B)"
    echo "  --help               Show this help message"
    exit 0
}

L4T_DIR=""
BOTH_SLOTS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --l4t-dir)
            shift
            L4T_DIR="$1"
            ;;
        --both-slots)
            BOTH_SLOTS=true
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

if [[ -z "$L4T_DIR" ]]; then
    echo "Error: --l4t-dir is required"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
Package: jetson-5.1.5-ekb-update
Version: 1.0
Section: base
Priority: optional
Architecture: arm64
Maintainer: Auto Generated
Description: OTA Update Payload for Jetson 5.1.5 with EKB
EOF

cp "$PAYLOAD" "$DEB_DIR/opt/ota_package/bl_only_payload"

cat > "$DEB_DIR/opt/ota_package/install_payload.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

UPDATE_ENGINE="/usr/sbin/nv_update_engine"

if [[ ! -x "$UPDATE_ENGINE" ]]; then
    chmod +x "$UPDATE_ENGINE"
fi

$UPDATE_ENGINE --install /opt/ota_package/bl_only_payload
EOF

chmod +x "$DEB_DIR/opt/ota_package/install_payload.sh"

if $BOTH_SLOTS; then
    cat > "$DEB_DIR/opt/ota_package/install_both_slots.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

UPDATE_ENGINE="/usr/sbin/nv_update_engine"

if [[ ! -x "$UPDATE_ENGINE" ]]; then
    chmod +x "$UPDATE_ENGINE"
fi

# Install on current slot
$UPDATE_ENGINE --install /opt/ota_package/bl_only_payload

# Mark to install on next slot after reboot
touch /opt/ota_package/slot_a_done.flag

# Switch slots and reboot
nvbootctrl --set-active-boot-slot 1
reboot
EOF
    chmod +x "$DEB_DIR/opt/ota_package/install_both_slots.sh"

    # Create systemd service for second-slot install
    mkdir -p "$DEB_DIR/etc/systemd/system"
    cat > "$DEB_DIR/etc/systemd/system/ota-second-slot.service" <<'EOF'
[Unit]
Description=OTA Second Slot Installer
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/opt/ota_package/install_payload.sh
ConditionPathExists=/opt/ota_package/slot_a_done.flag
ExecStartPost=/bin/rm -f /opt/ota_package/slot_a_done.flag

[Install]
WantedBy=multi-user.target
EOF

    cat > "$DEB_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/bash
set -e

# Enable the systemd service for slot B update
systemctl enable ota-second-slot.service
EOF
    chmod +x "$DEB_DIR/DEBIAN/postinst"
fi

OUTPUT_DEB="$SCRIPT_DIR/jetson-5.1.5-ekb-update.deb"
dpkg-deb --build "$DEB_DIR" "$OUTPUT_DEB"
echo "[*] Debian package created at $OUTPUT_DEB"

