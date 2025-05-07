#!/bin/bash

set -e

# --- CONFIG ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE_IP_FILE="$SCRIPT_DIR/../device_ip"

show_help() {
    cat <<EOF
Usage: sudo $0 --target-bsp <folder> [--force]
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

The target device IP must be provided in a file named 'device_ip' in the parent directory.

NOTE:
  The Tegra BSP package for the desired version must already be set up.
  See 'setup_tegra_package.sh' or 'setup_tegra_package_docker.sh' for details.
EOF
}

ensure_ssh_key() {
    if ! ssh -o BatchMode=yes -o ConnectTimeout=3 root@"$DEVICE_IP" true 2>/dev/null; then
        echo "🔑 SSH key not set up for root@$DEVICE_IP."
        echo "Would you like to run ssh-copy-id to install your public key? [Y/n]: "
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]?$ ]]; then
            echo "Running ssh-copy-id..."
            ssh-copy-id root@"$DEVICE_IP"
        else
            echo "Aborting: passwordless SSH is required to continue."
            exit 1
        fi
    fi
}

# --- CHECK ROOT ---
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run with sudo or as root."
    exit 1
fi

# --- PARSE ARGS ---
FORCE=0
CHECK_VAR=0
SWAP_SLOT=0
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
        --check-var)
            CHECK_VAR=1
            shift
            ;;
        --swap-slot)
            SWAP_SLOT=1
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

# --- CHECK DEVICE IP ---
DEVICE_IP=$(cat "$DEVICE_IP_FILE" 2>/dev/null)
if [[ -z "$DEVICE_IP" ]]; then
    echo "Error: Missing IP address in $DEVICE_IP_FILE"
    exit 1
fi

ensure_ssh_key

# --- ONLY CHECK OsIndications ---
if [[ "$CHECK_VAR" -eq 1 ]]; then
    echo "--- Current OsIndications value on $DEVICE_IP ---"
    ssh root@"$DEVICE_IP" "cat /sys/firmware/efi/efivars/OsIndications-8be4df61-93ca-11d2-aa0d-00e098032b8c | hexdump -C" || {
        echo "Failed to read OsIndications on device."
        exit 1
    }
    exit 0
fi

# --- ONLY SWAP SLOT ---
if [[ "$SWAP_SLOT" -eq 1 ]]; then
    echo "--- Checking current boot slot on $DEVICE_IP ---"
    CURRENT_SLOT=$(ssh root@"$DEVICE_IP" "nvbootctrl get-current-slot" 2>/dev/null)
    if [[ "$CURRENT_SLOT" != "0" && "$CURRENT_SLOT" != "1" ]]; then
        echo "Failed to get current boot slot (got '$CURRENT_SLOT')"
        exit 1
    fi
    NEW_SLOT=$((1 - CURRENT_SLOT))
    echo "Current slot: $CURRENT_SLOT"
    echo "Switching to slot: $NEW_SLOT"

    ssh root@"$DEVICE_IP" "nvbootctrl set-active-boot-slot $NEW_SLOT" || {
        echo "Failed to set active boot slot to $NEW_SLOT"
        exit 1
    }

    echo -n "Reboot device $DEVICE_IP now? [Y/n]: "
    read -r answer
    if [[ "$answer" =~ ^[Yy]?$ ]]; then
        echo "Rebooting..."
        ssh root@"$DEVICE_IP" "reboot"
    else
        echo "Reboot skipped."
    fi
    exit 0
fi

# --- REQUIRE target-bsp unless in check-only or swap-slot mode ---
if [[ -z "$TARGET_BSP" ]]; then
    echo "Error: --target-bsp is required unless using --check-var or --swap-slot"
    show_help
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

