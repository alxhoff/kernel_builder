#!/bin/bash

# Flash Jetson AGX Orin (QSPI + eMMC) for JetPack 7.x.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_L4T_DIR="$SCRIPT_DIR/Linux_for_Tegra"
DEFAULT_FLASH_KERNEL_DIR="$SCRIPT_DIR/flash_kernel"

MODE="direct"
L4T_DIR="$DEFAULT_L4T_DIR"
FLASH_KERNEL_DIR="$DEFAULT_FLASH_KERNEL_DIR"
DTB_FILE=""
DRY_RUN=false

to_absolute_path() {
  local path="$1"
  if [[ "$path" != /* ]]; then
    echo "$(realpath -s "$path")"
  else
    echo "$path"
  fi
}

resolve_jp7_bpmp_dtb() {
  local l4t_dir="$1"
  local sku="0000"
  if [[ -f "$l4t_dir/bootloader/ecid.bin" ]]; then
    # shellcheck disable=SC1090
    source "$l4t_dir/bootloader/ecid.bin" 2>/dev/null || true
    sku="${BOARDSKU:-0000}"
  fi
  case "$sku" in
    0004) echo "$l4t_dir/bootloader/generic/tegra234-bpmp-3701-0004-3737-0000.dtb" ;;
    0005) echo "$l4t_dir/bootloader/generic/tegra234-bpmp-3701-0005-3737-0000.dtb" ;;
    *)    echo "$l4t_dir/bootloader/generic/tegra234-bpmp-3701-0000-3737-0000.dtb" ;;
  esac
}

validate_jp7_flash_prereqs() {
  local conf="$L4T_DIR/p3701.conf.common"
  [[ -f "$conf" ]] || { echo "Error: missing $conf"; exit 1; }

  # shellcheck disable=SC1090
  source "$conf"
  if [[ "${target_board}" != "generic" ]]; then
    echo "Error: p3701.conf.common has target_board=\"${target_board}\" but JP7 requires \"generic\"."
    echo "  Fix: sed -i 's/^target_board=\"t186ref\";/target_board=\"generic\";/' \"$conf\""
    exit 1
  fi
  if [[ -z "${EMC_BCT:-}" ]]; then
    echo "Error: EMC_BCT is unset in $conf (JP7 flash.sh does not read EMMC_BCT)."
    echo "  Fix: sed -i 's/EMMC_BCT=/EMC_BCT=/g' \"$conf\""
    exit 1
  fi
  local bct_dir="$L4T_DIR/bootloader/${target_board}/BCT"
  if [[ ! -f "$bct_dir/${EMC_BCT}" ]]; then
    echo "Error: missing SDRAM BCT $bct_dir/${EMC_BCT}"
    exit 1
  fi
  local bpmp_dtb
  bpmp_dtb="$(resolve_jp7_bpmp_dtb "$L4T_DIR")"
  if [[ ! -f "$bpmp_dtb" ]]; then
    echo "Error: missing BPMP DTB $bpmp_dtb"
    exit 1
  fi
}

ensure_jp7_uefi_cpubl() {
  local bl="$L4T_DIR/bootloader"
  local tbc="$bl/uefi_jetson.bin"
  [[ -f "$tbc" ]] && return 0
  local candidate
  for candidate in \
    "$bl/uefi_jetson_with_dtb.bin" \
    "$bl/uefi_t23x_general.bin" \
    "$bl/uefi_bins/uefi_t23x_general.bin" \
    "$bl/uefi_bins/uefi_t23x_minimal.bin"; do
    if [[ -f "$candidate" ]]; then
      ln -sf "$(realpath --relative-to="$bl" "$candidate")" "$tbc"
      echo "JP7 flash: linked $tbc -> $(realpath --relative-to="$bl" "$candidate") (--cpubl for tegraflash.py)"
      return 0
    fi
  done
  echo "Error: missing $tbc (no UEFI payload under $bl or $bl/uefi_bins/)."
  echo "  tegraflash.py misparses --bins when --cpubl is empty, causing bpmp_fw_dtb errors."
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --l4t-dir) L4T_DIR="${2%/}"; shift 2 ;;
    --dtb-file) DTB_FILE="$2"; shift 2 ;;
    --flash-kernel-dir) FLASH_KERNEL_DIR="$2"; shift 2 ;;
    --kernel) MODE="copy-kernel"; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help) exit 0 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

L4T_DIR=$(to_absolute_path "$L4T_DIR")
BOOTLOADER_PARTITION_XML="$L4T_DIR/bootloader/generic/cfg/flash_t234_qspi_sdmmc.xml"
BOOTLOADER_PARTITION_XML=$(to_absolute_path "$BOOTLOADER_PARTITION_XML")
JP7_BPMP_DTB="$(to_absolute_path "$(resolve_jp7_bpmp_dtb "$L4T_DIR")")"

[[ "$DRY_RUN" == false ]] && validate_jp7_flash_prereqs
[[ "$DRY_RUN" == false ]] && ensure_jp7_uefi_cpubl

if [[ "$MODE" == "copy-kernel" ]]; then
  FLASH_KERNEL_DIR=$(to_absolute_path "$FLASH_KERNEL_DIR")
  KERNEL_IMAGE=$(find "$FLASH_KERNEL_DIR" -type f -name "Image.*" | head -n 1)
  [[ -n "$KERNEL_IMAGE" ]] || { echo "Error: No kernel image (Image.*) found in $FLASH_KERNEL_DIR"; exit 1; }
  STAGED_DTB=$(find "$FLASH_KERNEL_DIR" -type f -name "*.dtb" | head -n 1)
  [[ -n "$STAGED_DTB" ]] || { echo "Error: No DTB file (*.dtb) found in $FLASH_KERNEL_DIR"; exit 1; }
  MODULES_DIR=$(find "$FLASH_KERNEL_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
  [[ -n "$MODULES_DIR" ]] || { echo "Error: No kernel modules directory found in $FLASH_KERNEL_DIR"; exit 1; }

  if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$L4T_DIR/kernel" "$L4T_DIR/kernel/dtb"
    mkdir -p "$L4T_DIR/rootfs/boot" "$L4T_DIR/rootfs/boot/dtb" "$L4T_DIR/rootfs/lib/modules"
    cp "$KERNEL_IMAGE" "$L4T_DIR/kernel"
    cp "$KERNEL_IMAGE" "$L4T_DIR/rootfs/boot"
    cp "$KERNEL_IMAGE" "$L4T_DIR/rootfs/boot/Image"
    cp "$STAGED_DTB" "$L4T_DIR/kernel/dtb"
    cp "$STAGED_DTB" "$L4T_DIR/rootfs/boot/dtb"
    cp -r "$MODULES_DIR" "$L4T_DIR/rootfs/lib/modules"
  fi

  CMD="sudo ./flash.sh -c $BOOTLOADER_PARTITION_XML -g $JP7_BPMP_DTB jetson-agx-orin-devkit mmcblk0p1"
else
  KERNEL_IMAGE="$L4T_DIR/kernel/Image"
  if [[ -z "$DTB_FILE" ]]; then
    DTB_FILE="$L4T_DIR/kernel/dtb/tegra234-p3737-0000+p3701-0000.dtb"
  fi
  CMD="sudo ./flash.sh -c $BOOTLOADER_PARTITION_XML -g $JP7_BPMP_DTB -K $(to_absolute_path "$KERNEL_IMAGE") -d $(to_absolute_path "$DTB_FILE") jetson-agx-orin-devkit mmcblk0p1"
fi

[[ "$DRY_RUN" == false ]] && echo -1 | sudo tee /sys/module/usbcore/parameters/autosuspend
echo "Flash command: $CMD"
if [[ "$DRY_RUN" == false ]]; then
  pushd "$L4T_DIR" > /dev/null
  eval "$CMD"
  popd > /dev/null
fi
