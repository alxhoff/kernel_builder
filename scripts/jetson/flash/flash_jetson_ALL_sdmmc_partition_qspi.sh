#!/bin/bash

# Default values
DEFAULT_L4T_DIR="Cartken_Jetson_Image_35.4.1-standalone-20240516-1/Linux_for_Tegra"
BOOTLOADER_PARTITION_XML="bootloader/flash_t234_qspi_sdmmc.xml"
FLASH_KERNEL_DIR="$(dirname "$0")/flash_kernel"
COPY_KERNEL_FILES=false
DRY_RUN=false

# Functions
show_help() {
  cat << EOF
Usage: $0 [OPTIONS]

Flashes the Jetson AGX Orin with the specified kernel, DTB, and modules.

Options:
  --l4t-dir <path>    Path to the Linux_for_Tegra directory (default: $DEFAULT_L4T_DIR)
  --kernel            Copy kernel files (Image, DTB, and modules) to L4T directory and rootfs before flashing
  --dry-run           Print actions without executing them
  --help              Show this help message and exit
EOF
}

# Parse arguments
L4T_DIR="$DEFAULT_L4T_DIR"

while [[ $# -gt 0 ]]; do
  case $1 in
    --l4t-dir)
      L4T_DIR="${2%/}"  # Remove trailing slash if present
      shift 2
      ;;
    --kernel)
      COPY_KERNEL_FILES=true
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

to_absolute_path() {
  local path="$1"
  if [[ "$path" != /* ]]; then
    echo "$(realpath -s "$path")"
  else
    echo "$path"
  fi
}


# If --kernel is set, copy files to L4T directory and rootfs
if [[ "$COPY_KERNEL_FILES" == true ]]; then
	# Locate Kernel Image
	KERNEL_IMAGE=$(find "$FLASH_KERNEL_DIR" -type f -name "Image.*" | head -n 1)
	if [[ -z "$KERNEL_IMAGE" ]]; then
	  echo "Error: No kernel image (Image.*) found in $FLASH_KERNEL_DIR"
	  exit 1
	fi
	KERNEL_IMAGE=$(to_absolute_path "$KERNEL_IMAGE")

	# Locate DTB file
	DTB_FILE=$(find "$FLASH_KERNEL_DIR" -type f -name "*.dtb" | head -n 1)
	if [[ -z "$DTB_FILE" ]]; then
	  echo "Error: No DTB file (*.dtb) found in $FLASH_KERNEL_DIR"
	  exit 1
	fi
	DTB_FILE=$(to_absolute_path "$DTB_FILE")

	# Locate Kernel Modules Directory
	MODULES_DIR=$(find "$FLASH_KERNEL_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
	if [[ -z "$MODULES_DIR" ]]; then
	  echo "Error: No kernel modules directory found in $FLASH_KERNEL_DIR"
	  exit 1
	fi
	MODULES_DIR=$(to_absolute_path "$MODULES_DIR")

  echo "Copying kernel files to $L4T_DIR and rootfs..."

  # Ensure destination directories exist
  [[ "$DRY_RUN" == false ]] && mkdir -p "$L4T_DIR/kernel"
  [[ "$DRY_RUN" == false ]] && mkdir -p "$L4T_DIR/kernel/dtb"
  [[ "$DRY_RUN" == false ]] && mkdir -p "$L4T_DIR/rootfs/boot"
  [[ "$DRY_RUN" == false ]] && mkdir -p "$L4T_DIR/rootfs/boot/dtb"
  [[ "$DRY_RUN" == false ]] && mkdir -p "$L4T_DIR/rootfs/lib/modules"

  # Copy kernel image
  echo "Copy kernel image: cp $KERNEL_IMAGE -> $L4T_DIR/kernel"
  [[ "$DRY_RUN" == false ]] && cp "$KERNEL_IMAGE" "$L4T_DIR/kernel"

  echo "Copy kernel image: cp $KERNEL_IMAGE -> $L4T_DIR/rootfs/boot"
  [[ "$DRY_RUN" == false ]] && cp "$KERNEL_IMAGE" "$L4T_DIR/rootfs/boot"

  echo "Copy kernel image as 'Image': cp $KERNEL_IMAGE -> $L4T_DIR/rootfs/boot/Image"
  [[ "$DRY_RUN" == false ]] && cp "$KERNEL_IMAGE" "$L4T_DIR/rootfs/boot/Image"

  # Copy DTB file
  echo "Copy DTB file: cp $DTB_FILE -> $L4T_DIR/kernel/dtb"
  [[ "$DRY_RUN" == false ]] && cp "$DTB_FILE" "$L4T_DIR/kernel/dtb"

  echo "Copy DTB file: cp $DTB_FILE -> $L4T_DIR/rootfs/boot/dtb"
  [[ "$DRY_RUN" == false ]] && cp "$DTB_FILE" "$L4T_DIR/rootfs/boot/dtb"

  # Copy kernel modules
  echo "Copy kernel modules: cp -r $MODULES_DIR -> $L4T_DIR/rootfs/lib/modules"
  [[ "$DRY_RUN" == false ]] && cp -r "$MODULES_DIR" "$L4T_DIR/rootfs/lib/modules"
fi

# Run the flash command
BOOTLOADER_PARTITION_XML=$(to_absolute_path "$BOOTLOADER_PARTITION_XML")
CMD="./flash.sh -c $BOOTLOADER_PARTITION_XML jetson-agx-orin-devkit mmcblk0p1"

echo "Flash command: $CMD"
if [[ "$DRY_RUN" == false ]]; then
  pushd "$L4T_DIR"
  eval "$CMD"
  popd
fi

