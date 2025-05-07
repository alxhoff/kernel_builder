#!/bin/bash

set -e

# --- CONFIG ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE_IP_FILE="$SCRIPT_DIR/../device_ip"
REBOOT_TIMEOUT=120

show_help() {
    cat <<EOF
Usage: sudo $0 --target-bsp <folder> [--force] [--both-slots]
       sudo $0 --check-var
       sudo $0 --swap-slot

This script updates the bootloader on a remote Jetson device.

Required:
  --target-bsp <folder>   Folder (in the same directory as this script) containing
                          the Linux_for_Tegra directory (i.e. your ToT_BSP)

Optional:
  --force                 Regenerate the bootloader payload even if it already exists
  --check-var             Only print the current OsIndications variable via SSH and exit
  --swap-slot             Swap to the other boot slot using nvbootctrl, then optionally reboot
  --both-slots            Update both A/B slots with a reboot in between (requires --target-bsp)

The target device IP must be provided in a file named 'device_ip' in the parent directory.

NOTE:
  The Tegra BSP package for the desired version must already be set up.
  See 'setup_tegra_package.sh' or 'setup_tegra_package_docker.sh' for details.
EOF
}

ensure_ssh_key() {
    if ! ssh -o BatchMode=yes -o ConnectTimeout=3 root@"$DEVICE_IP" true 2>/dev/null; then
        echo "\n🔑 SSH key not set up for root@$DEVICE_IP."
        echo "Would you like to run ssh-copy-id to install your public key? [Y/n]: "
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]?$ ]]; then
            ssh-copy-id root@"$DEVICE_IP"
        else
            echo "Aborting: passwordless SSH is required to continue."
            exit 1
        fi
    fi
}

wait_for_ssh() {
    echo "⏳ Waiting for device $DEVICE_IP to become available (timeout ${REBOOT_TIMEOUT}s)..."
    sleep 30  # Initial grace period after reboot
    local start=$(date +%s)
    while ! ssh -o BatchMode=yes -o ConnectTimeout=3 root@"$DEVICE_IP" true 2>/dev/null; do
        sleep 2
        [[ $(($(date +%s) - start)) -gt $REBOOT_TIMEOUT ]] && {
            echo "❌ Timeout waiting for device to come back online."
            exit 1
        }
    done
    echo "✅ Device is back online."
}

update_bootloader() {
    echo "--- Updating bootloader on current slot..."

    ssh root@"$DEVICE_IP" bash <<'EOF'
set -e
mkdir -p /opt/nvidia/esp
esp_uuid=$(lsblk -o name,partlabel,uuid | grep "mmcblk0" | awk '{ if($2 == "esp") print $3 }')
mountpoint -q /opt/nvidia/esp || mount UUID=$esp_uuid /opt/nvidia/esp
EOF

    ssh root@"$DEVICE_IP" "mkdir -p /opt/nvidia/esp/EFI/UpdateCapsule"
    scp "$PAYLOAD" root@"$DEVICE_IP":/root/bl_only_payload
    ssh root@"$DEVICE_IP" "mv /root/bl_only_payload /opt/nvidia/esp/EFI/UpdateCapsule/"

    ssh root@"$DEVICE_IP" <<'EOF'
set -e
cd /sys/firmware/efi/efivars/
echo "--- Current OsIndications value ---"
cat OsIndications-8be4df61-93ca-11d2-aa0d-00e098032b8c | hexdump -C

printf "\x07\x00\x00\x00\x04\x00\x00\x00\x00\x00\x00\x00" > /tmp/var_tmp.bin
dd if=/tmp/var_tmp.bin of=OsIndications-8be4df61-93ca-11d2-aa0d-00e098032b8c bs=12
sync

echo "--- Updated OsIndications value ---"
cat OsIndications-* | hexdump -C
EOF
}

# --- CHECK ROOT ---
[[ "$EUID" -ne 0 ]] && { echo "This script must be run with sudo or as root."; exit 1; }

# --- PARSE ARGS ---
BUILD_ONLY=0
FORCE=0
USER_IP=""
CHECK_VAR=0
SWAP_SLOT=0
BOTH_SLOTS=0
TARGET_BSP=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-bsp) TARGET_BSP="$2"; shift 2;;
        --force) FORCE=1; shift;;
        --check-var) CHECK_VAR=1; shift;;
        --swap-slot) SWAP_SLOT=1; shift;;
        --both-slots) BOTH_SLOTS=1; shift;;
        --help|-h) show_help; exit 0;;
        --build-only) BUILD_ONLY=1; shift;;
        --ip) USER_IP="$2"; shift 2;;
        *) echo "Unknown argument: $1"; show_help; exit 1;;
    esac
done

DEVICE_IP=${USER_IP:-$(cat "$DEVICE_IP_FILE" 2>/dev/null)}
[[ -z "$DEVICE_IP" ]] && { echo "Error: Missing IP address in $DEVICE_IP_FILE"; exit 1; }

ensure_ssh_key

if [[ "$CHECK_VAR" -eq 1 ]]; then
    echo "--- Current OsIndications value on $DEVICE_IP ---"
    ssh root@"$DEVICE_IP" "cat /sys/firmware/efi/efivars/OsIndications-* | hexdump -C"
    exit 0
fi

if [[ "$SWAP_SLOT" -eq 1 ]]; then
    CURRENT_SLOT=$(ssh root@"$DEVICE_IP" "nvbootctrl get-current-slot")
    [[ "$CURRENT_SLOT" != "0" && "$CURRENT_SLOT" != "1" ]] && { echo "Invalid slot: $CURRENT_SLOT"; exit 1; }
    NEW_SLOT=$((1 - CURRENT_SLOT))
    echo "Switching from slot $CURRENT_SLOT to $NEW_SLOT..."
    ssh root@"$DEVICE_IP" "nvbootctrl set-active-boot-slot $NEW_SLOT"
    echo -n "Reboot device now? [Y/n]: "; read -r ans
    [[ "$ans" =~ ^[Yy]?$ ]] && ssh root@"$DEVICE_IP" reboot || echo "Reboot skipped."
    exit 0
fi

if [[ -z "$TARGET_BSP" ]]; then
    echo "Error: --target-bsp is required unless using --check-var or --swap-slot"
    show_help
    exit 1
fi

export ToT_BSP="$SCRIPT_DIR/$TARGET_BSP/Linux_for_Tegra"
cd "$ToT_BSP"
PAYLOAD="$ToT_BSP/bootloader/payloads_t23x/bl_only_payload"

if [[ ! -f "$PAYLOAD" || "$FORCE" -eq 1 ]]; then
    echo "Generating bootloader payload..."
    ./l4t_generate_soc_bup.sh -e t23x_agx_bl_spec t23x
fi

if [[ "$BUILD_ONLY" -eq 1 ]]; then
    echo "✅ Payload built at $PAYLOAD"
    exit 0
fi

if [[ "$BOTH_SLOTS" -eq 1 ]]; then
    echo "--- Step 1: Updating current slot ---"
    update_bootloader

    echo "Slot info after first update:"
    ssh root@"$DEVICE_IP" "nvbootctrl dump-slots-info" || echo "Warning: nvbootctrl failed"

    CURRENT_SLOT=$(ssh root@"$DEVICE_IP" "nvbootctrl get-current-slot")
    OTHER_SLOT=$((1 - CURRENT_SLOT))

    echo "Rebooting to other slot ($OTHER_SLOT)..."
    ssh root@"$DEVICE_IP" "nvbootctrl set-active-boot-slot $OTHER_SLOT" || true
    ssh root@"$DEVICE_IP" reboot || true
    wait_for_ssh

    echo "--- Step 2: Updating new active slot ---"
    update_bootloader

    echo "Waiting for device to reboot..."
    ssh root@"$DEVICE_IP" reboot || true
    wait_for_ssh

    echo "Final slot info after both updates:"
    ssh root@"$DEVICE_IP" "nvbootctrl dump-slots-info" || echo "Warning: nvbootctrl failed"
    echo "--- Done"

    echo "✅ Bootloader update applied to both slots."
    exit 0
fi

ssh root@"$DEVICE_IP" "nvbootctrl dump-slots-info" || echo "Warning: nvbootctrl failed"
update_bootloader

echo "✅ Bootloader update complete on device $DEVICE_IP"
echo "⚠️  A reboot is required for the changes to take effect."

