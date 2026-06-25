#!/usr/bin/env bash
# Force JP6/JP7 UEFI to load kernel+DTB from rootfs (extlinux), not QSPI/partition fallbacks.
#
# NVIDIA L4TDefaultBootMode (efivar):
#   01 00 00 00 = kernel + DTB from filesystem (extlinux FDT)
#   02 00 00 00 = kernel + DTB from eMMC partitions (A_kernel-dtb, etc.)
#
# Without mode 01, extlinux FDT may be ignored even when present. When DTB load/overlay
# merge then fails on the partition path, UEFI falls back to the stock QSPI embedded tree
# (num-channels=2 on devkit).
#
# Usage (on robot, as root):
#   ./ensure_l4t_rootfs_dtb_boot.sh [--check-only] [--dry-run]

set -euo pipefail

L4T_BOOT_MODE_VAR_GLOB="/sys/firmware/efi/efivars/L4TDefaultBootMode-*"
# UEFI variable header + little-endian uint32 value 0x00000001
FILESYSTEM_BOOT_MODE=$'\x07\x00\x00\x00\x01\x00\x00\x00'

CHECK_ONLY=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check-only) CHECK_ONLY=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help)
            sed -n '2,14p' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ ! -d /sys/firmware/efi/efivars ]]; then
    echo "Error: EFI variables not available (not a UEFI Jetson boot?)" >&2
    exit 1
fi

shopt -s nullglob
vars=( $L4T_BOOT_MODE_VAR_GLOB )
shopt -u nullglob

if [[ ${#vars[@]} -eq 0 ]]; then
    echo "Error: L4TDefaultBootMode efivar not found under /sys/firmware/efi/efivars/" >&2
    exit 1
fi

L4T_VAR="${vars[0]}"
current_mode="$(hexdump -n 8 -e '8/1 "%02x"' "$L4T_VAR" 2>/dev/null || true)"
mode_value="${current_mode:8:8}"

echo "L4TDefaultBootMode efivar: $L4T_VAR"
echo "  raw:        $current_mode"
echo "  boot mode:  ${mode_value:-unknown} (want 01000000 = filesystem / extlinux DTB)"

case "$mode_value" in
    01000000) mode_name="filesystem (extlinux)" ;;
    02000000) mode_name="partitions (A_kernel-dtb)" ;;
    03000000) mode_name="recovery partitions" ;;
    00000000) mode_name="GRUB" ;;
    *) mode_name="unknown" ;;
esac
echo "  meaning:    $mode_name"

if [[ -f /boot/extlinux/extlinux.conf ]]; then
    echo
    echo "extlinux FDT:"
    grep -E '^[[:space:]]*FDT ' /boot/extlinux/extlinux.conf || echo "  (no FDT line — UEFI will not use rootfs DTB by default on JP6/JP7 AGX)"
else
    echo
    echo "Warning: /boot/extlinux/extlinux.conf not found" >&2
fi

if command -v fdtget &>/dev/null && [[ -f /sys/firmware/fdt ]]; then
    live_channels="$(fdtget /sys/firmware/fdt /tegra-capture-vi num-channels 2>/dev/null || echo "?")"
    echo
    echo "live /sys/firmware/fdt tegra-capture-vi num-channels: $live_channels"
fi

if [[ "$mode_value" == "01000000" ]]; then
    echo
    echo "Boot mode already set to filesystem/extlinux."
    exit 0
fi

if [[ "$CHECK_ONLY" == true ]]; then
    echo
    echo "Boot mode is NOT filesystem (01). Re-run without --check-only to fix."
    exit 1
fi

echo
echo "Setting L4TDefaultBootMode -> filesystem (01 00 00 00)..."

if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] chattr -i $L4T_VAR"
    echo "[dry-run] write $FILESYSTEM_BOOT_MODE to $L4T_VAR"
    echo "[dry-run] chattr +i $L4T_VAR"
    exit 0
fi

chattr -i "$L4T_VAR"
printf '%s' "$FILESYSTEM_BOOT_MODE" > "$L4T_VAR"
sync
chattr +i "$L4T_VAR"

echo "Done. Cold reboot for the change to take effect."
