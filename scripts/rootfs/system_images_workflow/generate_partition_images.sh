#!/bin/bash

# Default values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_L4T_DIR="$SCRIPT_DIR/cartken_flash/Linux_for_Tegra"

# Functions
show_help() {
  cat << EOF
Usage: $0 [OPTIONS]

Flashes the Jetson AGX Orin with the specified kernel, DTB, and modules.

Options:
  --l4t-dir <path>    Path to the Linux_for_Tegra directory (default: $DEFAULT_L4T_DIR)
  --help              Show this help message and exit
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


# Parse arguments
L4T_DIR="$DEFAULT_L4T_DIR"

while [[ $# -gt 0 ]]; do
  case $1 in
    --l4t-dir)
      L4T_DIR="${2%/}"  # Remove trailing slash if present
      shift 2
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

BOOTLOADER_PARTITION_XML="$L4T_DIR/bootloader/t186ref/cfg/flash_t234_qspi_sdmmc.xml"
KERNEL_IMAGE="$L4T_DIR/kernel/Image"
DTB_FILE="$L4T_DIR/kernel/dtb/tegra234-p3701-0000-p3737-0000.dtb"
BOOTLOADER_PARTITION_XML=$(to_absolute_path "$BOOTLOADER_PARTITION_XML")
KERNEL_IMAGE=$(to_absolute_path "$KERNEL_IMAGE")
DTB_FILE=$(to_absolute_path "$DTB_FILE")

# Run the flash command
CMD="BOARDID=3701 BOARDSKU=0000 FAB=TS4 $L4T_DIR/flash.sh --no-flash -c $BOOTLOADER_PARTITION_XML -K $KERNEL_IMAGE -d $DTB_FILE jetson-agx-orin-devkit mmcblk0p1"

pushd "$L4T_DIR"
echo "Flash command: $CMD"
eval "$CMD"
popd
