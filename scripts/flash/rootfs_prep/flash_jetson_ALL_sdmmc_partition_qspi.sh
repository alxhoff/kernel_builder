#!/bin/bash

# Flash Jetson AGX Orin (QSPI + eMMC) using Linux_for_Tegra's flash.sh.
#
# Two modes are supported via --mode:
#   direct      (default) Pass the kernel Image and DTB to flash.sh via -K/-d.
#   copy-kernel Copy a built kernel+DTB+modules from a staging directory
#               (default: $(dirname)/flash_kernel) into the L4T tree and
#               rootfs before running flash.sh without -K/-d.

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

Flashes the Jetson AGX Orin with the specified kernel, DTB, and modules.

Options:
  --mode <direct|copy-kernel>  Flash flow (default: $MODE)
  --l4t-dir <path>             Linux_for_Tegra directory (default: $DEFAULT_L4T_DIR)
  --dtb-file <path>            DTB file to pass to flash.sh (direct mode)
  --flash-kernel-dir <path>    Staging dir for copy-kernel mode
                               (default: $DEFAULT_FLASH_KERNEL_DIR)
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
  case $1 in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --l4t-dir)
      L4T_DIR="${2%/}"
      shift 2
      ;;
    --dtb-file)
      DTB_FILE="$2"
      shift 2
      ;;
    --flash-kernel-dir)
      FLASH_KERNEL_DIR="$2"
      shift 2
      ;;
    --kernel)
      # Compatibility shim for the old jetson/flash copy-kernel flag.
      MODE="copy-kernel"
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help)
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

L4T_DIR=$(to_absolute_path "$L4T_DIR")
L4T_VERSION=$(basename "$(dirname "$L4T_DIR")")

case "$L4T_VERSION" in
    6*)
        BOOTLOADER_PARTITION_XML="$L4T_DIR/bootloader/generic/cfg/flash_t234_qspi_sdmmc.xml"
        ;;
    *)
        BOOTLOADER_PARTITION_XML="$L4T_DIR/bootloader/t186ref/cfg/flash_t234_qspi_sdmmc.xml"
        ;;
esac
BOOTLOADER_PARTITION_XML=$(to_absolute_path "$BOOTLOADER_PARTITION_XML")

if [[ "$MODE" == "copy-kernel" ]]; then
    FLASH_KERNEL_DIR=$(to_absolute_path "$FLASH_KERNEL_DIR")

    KERNEL_IMAGE=$(find "$FLASH_KERNEL_DIR" -type f -name "Image.*" | head -n 1)
    if [[ -z "$KERNEL_IMAGE" ]]; then
        echo "Error: No kernel image (Image.*) found in $FLASH_KERNEL_DIR"
        exit 1
    fi
    KERNEL_IMAGE=$(to_absolute_path "$KERNEL_IMAGE")

    STAGED_DTB=$(find "$FLASH_KERNEL_DIR" -type f -name "*.dtb" | head -n 1)
    if [[ -z "$STAGED_DTB" ]]; then
        echo "Error: No DTB file (*.dtb) found in $FLASH_KERNEL_DIR"
        exit 1
    fi
    STAGED_DTB=$(to_absolute_path "$STAGED_DTB")

    MODULES_DIR=$(find "$FLASH_KERNEL_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    if [[ -z "$MODULES_DIR" ]]; then
        echo "Error: No kernel modules directory found in $FLASH_KERNEL_DIR"
        exit 1
    fi
    MODULES_DIR=$(to_absolute_path "$MODULES_DIR")

    echo "Copying kernel files to $L4T_DIR and rootfs..."

    if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$L4T_DIR/kernel" "$L4T_DIR/kernel/dtb"
        mkdir -p "$L4T_DIR/rootfs/boot" "$L4T_DIR/rootfs/boot/dtb" "$L4T_DIR/rootfs/lib/modules"
    fi

    echo "Copy kernel image: cp $KERNEL_IMAGE -> $L4T_DIR/kernel"
    [[ "$DRY_RUN" == false ]] && cp "$KERNEL_IMAGE" "$L4T_DIR/kernel"
    echo "Copy kernel image: cp $KERNEL_IMAGE -> $L4T_DIR/rootfs/boot"
    [[ "$DRY_RUN" == false ]] && cp "$KERNEL_IMAGE" "$L4T_DIR/rootfs/boot"
    echo "Copy kernel image as 'Image': cp $KERNEL_IMAGE -> $L4T_DIR/rootfs/boot/Image"
    [[ "$DRY_RUN" == false ]] && cp "$KERNEL_IMAGE" "$L4T_DIR/rootfs/boot/Image"
    echo "Copy DTB file: cp $STAGED_DTB -> $L4T_DIR/kernel/dtb"
    [[ "$DRY_RUN" == false ]] && cp "$STAGED_DTB" "$L4T_DIR/kernel/dtb"
    echo "Copy DTB file: cp $STAGED_DTB -> $L4T_DIR/rootfs/boot/dtb"
    [[ "$DRY_RUN" == false ]] && cp "$STAGED_DTB" "$L4T_DIR/rootfs/boot/dtb"
    echo "Copy kernel modules: cp -r $MODULES_DIR -> $L4T_DIR/rootfs/lib/modules"
    [[ "$DRY_RUN" == false ]] && cp -r "$MODULES_DIR" "$L4T_DIR/rootfs/lib/modules"

    CMD="sudo ./flash.sh -c $BOOTLOADER_PARTITION_XML jetson-agx-orin-devkit mmcblk0p1"
else
    KERNEL_IMAGE="$L4T_DIR/kernel/Image"
    if [ -z "$DTB_FILE" ]; then
        DTB_FILE="$L4T_DIR/kernel/dtb/tegra234-p3701-0000-p3737-0000.dtb"
    fi
    KERNEL_IMAGE=$(to_absolute_path "$KERNEL_IMAGE")
    DTB_FILE=$(to_absolute_path "$DTB_FILE")

    CMD="sudo ./flash.sh -c $BOOTLOADER_PARTITION_XML -K $KERNEL_IMAGE -d $DTB_FILE jetson-agx-orin-devkit mmcblk0p1"
fi

echo "Disabling USB autosuspend"
[[ "$DRY_RUN" == false ]] && echo -1 | sudo tee /sys/module/usbcore/parameters/autosuspend

echo "Flash command: $CMD"
if [[ "$DRY_RUN" == false ]]; then
    pushd "$L4T_DIR" > /dev/null
    eval "$CMD"
    popd > /dev/null
fi
