#!/usr/bin/env bash
# Pre-merge JP7 platform overlays into the Cartken camera DTB for rootfs/extlinux boot.
#
# Platform .dtbo files ship in the BSP (Linux_for_Tegra/kernel/dtb/) but are not on the
# robot rootfs by default — they normally live in QSPI. UEFI skips QSPI overlays when
# extlinux FDT is set, so the base camera DTB must already contain carveouts/optee/etc.
#
# Usage:
#   On flash host (before scp to robot):
#     ./merge_cartken_jp7_dtb.sh --l4t-dir /path/to/Linux_for_Tegra
#
#   On robot (after copying .dtbo files to /boot/dtb/):
#     ./merge_cartken_jp7_dtb.sh --dtb-dir /boot/dtb --update-extlinux
#
#   Deploy merged blob only:
#     ./merge_cartken_jp7_dtb.sh --l4t-dir ... --output /tmp/merged.dtb
#     scp /tmp/merged.dtb root@cart998:/boot/dtb/tegra234-p3701-0000-p3737-0000.dtb

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../flash/rootfs_prep/helpers/build_kernel.sh
JP7_PLATFORM_OVERLAY_DTBOS=(
    "L4TConfiguration.dtbo"
    "tegra234-p3737-0000+p3701-0000-dynamic.dtbo"
    "tegra234-carveouts.dtbo"
    "tegra-optee.dtbo"
    "T234SetFmpImageTypeGuid.dtbo"
)

L4T_DIR=""
DTB_DIR=""
BASE_DTB=""
OUTPUT=""
UPDATE_EXTLINUX=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --l4t-dir) L4T_DIR="${2%/}"; shift 2 ;;
        --dtb-dir) DTB_DIR="${2%/}"; shift 2 ;;
        --base-dtb) BASE_DTB="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        --update-extlinux) UPDATE_EXTLINUX=true; shift ;;
        --help)
            sed -n '2,20p' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -n "$L4T_DIR" ]]; then
    DTB_DIR="$L4T_DIR/kernel/dtb"
fi

if [[ -z "$DTB_DIR" ]]; then
    echo "Error: pass --l4t-dir or --dtb-dir" >&2
    exit 1
fi

if [[ -z "$BASE_DTB" ]]; then
    for candidate in \
        "$DTB_DIR/tegra234-p3701-0000-p3737-0000.dtb" \
        "$DTB_DIR/tegra234-p3737-0000+p3701-0000-nv.dtb"; do
        if [[ -f "$candidate" ]]; then
            BASE_DTB="$candidate"
            break
        fi
    done
fi

if [[ -z "$BASE_DTB" || ! -f "$BASE_DTB" ]]; then
    echo "Error: Cartken camera DTB not found under $DTB_DIR" >&2
    exit 1
fi

if [[ -z "$OUTPUT" ]]; then
    OUTPUT="$DTB_DIR/tegra234-cartken-merged.dtb"
fi

if ! command -v fdtoverlay &>/dev/null; then
    echo "Error: fdtoverlay not found (device-tree-compiler package)" >&2
    exit 1
fi

overlay_paths=()
missing=()
for dtbo in "${JP7_PLATFORM_OVERLAY_DTBOS[@]}"; do
    if [[ -f "$DTB_DIR/$dtbo" ]]; then
        overlay_paths+=("$DTB_DIR/$dtbo")
    else
        missing+=("$DTB_DIR/$dtbo")
    fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: missing platform overlay(s):" >&2
    printf '  %s\n' "${missing[@]}" >&2
    echo >&2
    echo "Copy them from the flash host BSP, e.g.:" >&2
    echo "  Linux_for_Tegra/kernel/dtb/L4TConfiguration.dtbo \\" >&2
    echo "  Linux_for_Tegra/kernel/dtb/tegra234-p3737-0000+p3701-0000-dynamic.dtbo \\" >&2
    echo "  Linux_for_Tegra/kernel/dtb/tegra234-carveouts.dtbo \\" >&2
    echo "  Linux_for_Tegra/kernel/dtb/tegra-optee.dtbo \\" >&2
    echo "  Linux_for_Tegra/kernel/dtb/T234SetFmpImageTypeGuid.dtbo" >&2
    exit 1
fi

echo "Base:     $BASE_DTB"
echo "Overlays: ${#overlay_paths[@]} file(s) from $DTB_DIR"
echo "Output:   $OUTPUT"

fdtoverlay -i "$BASE_DTB" -o "$OUTPUT" "${overlay_paths[@]}"

if command -v fdtget &>/dev/null; then
    channels="$(fdtget "$OUTPUT" /tegra-capture-vi num-channels 2>/dev/null || echo "?")"
    echo "Merged DTB tegra-capture-vi num-channels=$channels (expect 14)"
fi

if [[ "$UPDATE_EXTLINUX" == true ]]; then
    EXTLINUX=/boot/extlinux/extlinux.conf
    if [[ ! -f "$EXTLINUX" ]]; then
        echo "Error: $EXTLINUX not found" >&2
        exit 1
    fi
    abs_fdt="/boot/dtb/$(basename "$OUTPUT")"
    if grep -q '^[[:space:]]*FDT ' "$EXTLINUX"; then
        sed -i "s|^[[:space:]]*FDT .*|      FDT ${abs_fdt}|" "$EXTLINUX"
    else
        sed -i "/^[[:space:]]*LINUX /a \      FDT ${abs_fdt}" "$EXTLINUX"
    fi
    sed -i '/^[[:space:]]*OVERLAYS /d' "$EXTLINUX"
    echo "Updated extlinux FDT -> $abs_fdt"
fi

echo "Done. Cold reboot to apply."
