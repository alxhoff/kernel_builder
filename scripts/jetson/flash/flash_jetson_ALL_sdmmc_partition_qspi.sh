#!/bin/bash

# Default values
DEFAULT_L4T_DIR="Cartken_Jetson_Image_35.4.1-standalone-20240516-1/Linux_for_Tegra/"
ROOTDISK_PARTITION_XML=""
BOOTLOADER_PARTITION_XML="bootloader/flash_t234_qspi_sdmmc.xml"

# Functions
show_help() {
  cat << EOF

EOF
}

# Parse arguments
L4T_DIR="$DEFAULT_L4T_DIR"

while [[ $# -gt 0 ]]; do
  case $1 in
    --l4t-dir)
      L4T_DIR="$2"
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

to_absolute_path() {
  local path="$1"
  if [[ "$path" != /* ]]; then
    echo "$(realpath -s "$path")"
  else
    echo "$path"
  fi
}

# Run the command
BOOTLOADER_PARTITION_XML=$(to_absolute_path "$BOOTLOADER_PARTITION_XML")
pushd "$L4T_DIR"
CMD="./flash.sh -c $BOOTLOADER_PARTITION_XML  jetson-agx-orin-devkit mmcblk0p1"
echo "Running: $CMD"
eval "$CMD"
popd

