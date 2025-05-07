#!/bin/bash

set -e

# --- CONFIG ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE_IP_FILE="$SCRIPT_DIR/../device_ip"

show_help() {
    cat <<EOF
Usage: sudo $0 --target-bsp <folder> [--force]

This script updates the bootloader on a remote Jetson device.

Required:
  --target-bsp <folder>   Folder (in the same directory as this script) containing
                          the Linux_for_Tegra directory (i.e. your ToT_BSP)

Optional:
  --force                 Regenerate the bootloader payload even if it already exists

The target device IP must be provided in a file named 'device_ip' in the parent directory.

NOTE:
  The Tegra BSP package for the desired version must already be set up.
  See 'setup_tegra_package.sh' or 'setup_tegra_package_docker.sh' for details.
EOF
}

# --- CHECK ROOT ---
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run with sudo or as root."
    exit 1
fi

# --- PARSE ARGS ---
FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-bsp)
            TARGET_BSP="$2"
            shift 2
            ;;
        --force)
            FORCE=1
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            show_help
            exit 1
            ;;
    esac
done

if [[ -z "$TARGET_BSP" ]]; then
    echo "Error: --target-bsp is required"
    show_help
    exit 1
fi

# --- CHECK DEVICE IP ---
DEVICE_IP=$(cat "$DEVICE_IP_FILE" 2>/dev/null)
if [[ -z "$DEVICE_IP" ]]; then
    echo "Error: Missing IP address in $DEVICE_IP_FILE"
    exit 1
fi

# --- SET ToT_BSP ---
export ToT_BSP="$SCRIPT_DIR/$TARGET_BSP/Linux_for_Tegra"
cd "$ToT_BSP"

PAYLOAD="$ToT_BSP/bootloader/payloads_t23x/bl_only_payload"

# --- GENERATE PAYLOAD IF NEEDED ---
if [[ -f "$PAYLOAD" && "$FORCE" -eq 0 ]]; then
    echo "Payload already exists at $PAYLOAD, skipping generation."
else
    echo "Generating payload..."
    ./l4t_generate_soc_bup.sh -e t23x_agx_bl_spec t23x
    if [[ ! -f "$PAYLOAD" ]]; then
        echo "Error: Payload generation failed or output not found at $PAYLOAD"
        exit 1
    fi
fi

# --- SHOW CURRENT DEVICE BOOT SLOT INFO ---
echo
echo "--- Current Boot Slot Info on Target Device ($DEVICE_IP) ---"
ssh root@"$DEVICE_IP" "nvbootctrl dump-slots-info" || echo "Warning: nvbootctrl not available or failed."

# --- PREPARE TARGET DEVICE ---
ssh root@"$DEVICE_IP" <<'EOF'
set -e
mkdir -p /opt/nvidia/esp
esp_uuid=$(lsblk -o name,partlabel,uuid | grep "mmcblk0" | awk '{ if($2 == "esp") print $3 }')
mount UUID=$esp_uuid /opt/nvidia/esp
EOF

# --- COPY PAYLOAD ---
scp "$PAYLOAD" root@"$DEVICE_IP":/opt/nvidia/esp/

# --- MODIFY OsIndications ---
ssh root@"$DEVICE_IP" <<'EOF'
set -e

echo
echo "--- Current OsIndications value ---"
cat /sys/firmware/efi/efivars/OsIndications-8be4df61-93ca-11d2-aa0d-00e098032b8c | hexdump -C

cd /sys/firmware/efi/efivars/
printf "\x07\x00\x00\x00\x04\x00\x00\x00\x00\x00\x00\x00" > /tmp/var_tmp.bin
dd if=/tmp/var_tmp.bin of=OsIndications-8be4df61-93ca-11d2-aa0d-00e098032b8c bs=12
sync

echo
echo "--- Updated OsIndications value ---"
cat /sys/firmware/efi/efivars/OsIndications-8be4df61-93ca-11d2-aa0d-00e098032b8c | hexdump -C
EOF

echo
echo "✅ Bootloader update complete on device $DEVICE_IP"
echo "⚠️  A reboot is required for the changes to take effect."

