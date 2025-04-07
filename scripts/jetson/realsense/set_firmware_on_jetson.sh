#!/bin/bash
set -e

BIN_PATH=$(find /xavier_ssd/docker/overlay2/ -name "Signed_Image_UVC_5_16_1_11?.bin" | grep -E "111|112" | sort)

DRY_RUN=false
BIN_FILE=""

for arg in "$@"; do
    case "$arg" in
        --111) BIN_FILE=$(echo "$BIN_PATH" | grep 111 | head -n1);;
        --112) BIN_FILE=$(echo "$BIN_PATH" | grep 112 | head -n1);;
        --dry-run) DRY_RUN=true;;
        *) echo "Unknown option: $arg" && exit 1;;
    esac
done

if [[ -z "$BIN_FILE" ]]; then
    echo "Error: No matching bin file found or version not specified."
    exit 1
fi

TARGETS=(
    /dev/d4xx-dfu-30-001a
    /dev/d4xx-dfu-30-001b
    /dev/d4xx-dfu-31-001c
    /dev/d4xx-dfu-31-001d
)

echo "Current firmware"
docker exec release rs-fw-update -l

for dev in "${TARGETS[@]}"; do
    echo "Flashing $BIN_FILE → $dev"
    $DRY_RUN || sudo cat "$BIN_FILE" > "$dev"
done

echo "Firmware now at"
docker exec release rs-fw-update -l

