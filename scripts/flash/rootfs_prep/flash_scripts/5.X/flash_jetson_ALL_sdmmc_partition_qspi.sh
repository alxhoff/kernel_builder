#!/bin/bash

# Flash Jetson AGX Orin (QSPI + eMMC) for JetPack 5.x.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_L4T_DIR="$SCRIPT_DIR/Linux_for_Tegra"
DEFAULT_FLASH_KERNEL_DIR="$SCRIPT_DIR/flash_kernel"

MODE="direct"
L4T_DIR="$DEFAULT_L4T_DIR"
FLASH_KERNEL_DIR="$DEFAULT_FLASH_KERNEL_DIR"
DTB_FILE=""
DRY_RUN=false

show_help() {
  cat << EOF
Usage: $0 [OPTIONS]

Options:
  --mode <direct|copy-kernel>  Flash flow (default: $MODE)
  --l4t-dir <path>             Linux_for_Tegra directory (default: $DEFAULT_L4T_DIR)
  --dtb-file <path>            DTB file to pass to flash.sh (direct mode)
  --flash-kernel-dir <path>    Staging dir for copy-kernel mode (default: $DEFAULT_FLASH_KERNEL_DIR)
  --dry-run                    Print actions without executing them
  --help                       Show this help message and exit
EOF
}

to_absolute_path() {
  local path="$1"
  if [[ "$path" != /* ]]; then
    echo "$(realpath -s "$path")"
  else
    echo "$path"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --l4t-dir) L4T_DIR="${2%/}"; shift 2 ;;
    --dtb-file) DTB_FILE="$2"; shift 2 ;;
    --flash-kernel-dir) FLASH_KERNEL_DIR="$2"; shift 2 ;;
    --kernel) MODE="copy-kernel"; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help) show_help; exit 0 ;;
    *) echo "Unknown argument: $1"; show_help; exit 1 ;;
  esac
done

L4T_DIR=$(to_absolute_path "$L4T_DIR")
BOOTLOADER_PARTITION_XML="$L4T_DIR/bootloader/t186ref/cfg/flash_t234_qspi_sdmmc.xml"
BOOTLOADER_PARTITION_XML=$(to_absolute_path "$BOOTLOADER_PARTITION_XML")

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

  CMD="sudo ./flash.sh -c $BOOTLOADER_PARTITION_XML jetson-agx-orin-devkit mmcblk0p1"
else
  KERNEL_IMAGE="$L4T_DIR/kernel/Image"
  if [[ -z "$DTB_FILE" ]]; then
    DTB_FILE="$L4T_DIR/kernel/dtb/tegra234-p3701-0000-p3737-0000.dtb"
  fi
  CMD="sudo ./flash.sh -c $BOOTLOADER_PARTITION_XML -K $(to_absolute_path "$KERNEL_IMAGE") -d $(to_absolute_path "$DTB_FILE") jetson-agx-orin-devkit mmcblk0p1"
fi

[[ "$DRY_RUN" == false ]] && echo -1 | sudo tee /sys/module/usbcore/parameters/autosuspend
echo "Flash command: $CMD"
if [[ "$DRY_RUN" == false ]]; then
  pushd "$L4T_DIR" > /dev/null
  eval "$CMD"
  popd > /dev/null
fi
