#!/bin/bash

# Default values
DEFAULT_L4T_DIR="Cartken_Jetson_Image_35.4.1-standalone-20240516-1/Linux_for_Tegra/"
ROOTDISK_PARTITION_XML="rootdisk/flash_l4t_external_no_kernel.xml"
BOOTLOADER_PARTITION_XML="bootloader/flash_t234_qspi.xml"

# Functions
show_help() {
  cat << EOF
Usage: $0 [OPTIONS]

Options:
  --l4t-dir DIR                    Override the default L4T directory (default: $DEFAULT_L4T_DIR).
  --help                           Show this help message and exit.

Description:
This script runs the following command:
  sudo ./flash_jetson.sh --l4t-dir [L4T_DIR] --rootdisk-partition-xml $ROOTDISK_PARTITION_XML --bootloader-partition-xml $BOOTLOADER_PARTITION_XML

You can override the default L4T directory using the --l4t-dir option.

Example:
  $0 --l4t-dir /path/to/your/Linux_for_Tegra/
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

# Run the command
CMD="sudo ./flash_jetson.sh --l4t-dir $L4T_DIR --rootdisk-partition-xml $ROOTDISK_PARTITION_XML --bootloader-partition-xml $BOOTLOADER_PARTITION_XML"
echo "Running: $CMD"
eval "$CMD"

