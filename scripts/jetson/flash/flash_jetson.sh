#!/bin/bash

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Constants
DEFAULT_L4T_DIR="Linux_for_Tegra"

# Variables
L4T_DIR=""
BOOTLOADER_PARTITION_XML=""
ROOTDISK_PARTITION_XML=""
BOOT_ORDER_OVERLAY=""
DRY_RUN=0
SKIP_ROOTFS_FLASH=0

# Functions
to_absolute_path() {
  local path="$1"
  if [[ "$path" != /* ]]; then
    echo "$(realpath -s "$path")"
  else
    echo "$path"
  fi
}

confirm_command() {
  local cmd="$1"
  read -p "Run this command? [Y/n]: $cmd " confirm
  confirm=${confirm,,} # Convert to lowercase
  if [[ "$confirm" == "n" || "$confirm" == "no" ]]; then
    echo "Command skipped."
    return 1
  fi
  return 0
}

show_help() {
  cat << 'EOF'
Usage: $0 [OPTIONS]

Options:
  --l4t-dir DIR                    Path to the Linux_for_Tegra directory (required if no tar is specified).
  --bootloader-partition-xml FILE  Bootloader partition XML configuration file. This file specifies the layout of
                                    the device's bootloader-related partitions.
  --rootdisk-partition-xml FILE    Root disk partition XML configuration file. This file specifies the layout
                                    of the root disk, including essential partitions like the root filesystem.
  --boot-order-overlay FILE        Path to the boot order overlay DTB file. If provided, it is passed as the
                                    ADDITIONAL_DTB_OVERLAY environment variable during the flash.sh call.
  "--dry-run                        Perform a dry run without executing commands. Commands will be displayed and
                                    confirmed interactively.
  --help                           Show this help message and exit.

Partition Configuration Details:
--------------------------------

### Bootloader Partition XML:
The bootloader partition XML defines the layout for the internal storage of the device used by the bootloader and firmware components. This configuration typically includes partitions for boot configuration tables (BCT), firmware, and other critical binaries required during the boot process.

#### Key Elements:
- `<partition_layout>`: Root element defining the version and layout.
- `<device>`: Represents a storage device (e.g., SPI flash) with attributes such as `type`, `instance`, `sector_size`, and `num_sectors`.
- `<partition>`: Defines a specific partition with attributes:
  - `name`: Partition name (e.g., `BCT`, `A_mb1`, etc.).
  - `type`: Type of partition (e.g., `boot_config_table`, `mb1_bootloader`).
  - `size`: Size of the partition in bytes.
  - `filename`: (Optional) Specifies the file to be flashed to this partition.
  - `allocation_policy`: Defines how the partition is allocated (e.g., `sequential`).
  - `align_boundary`: (Optional) Ensures the partition starts at a specified byte boundary.

#### Example:
```xml
<partition name="A_mb1" type="mb1_bootloader">
    <allocation_policy> sequential </allocation_policy>
    <filesystem_type> basic </filesystem_type>
    <size> 524288 </size>
    <filename> MB1FILE </filename>
    <align_boundary> 262144 </align_boundary>
</partition>
```
- `A_mb1`: The partition name for the MB1 bootloader.
- `sequential`: The partition is allocated sequentially after the previous partition.
- `524288`: The partition is 512 KB in size.
- `MB1FILE`: The binary file for this partition.

---

### Rootdisk Partition XML:
The rootdisk partition XML defines the layout for the root disk (external storage), which typically includes the root filesystem and necessary metadata like the master boot record (MBR) and GUID partition table (GPT).

#### Key Elements:
- `<partition_layout>`: Root element defining the layout for the external storage.
- `<device>`: Represents an external storage device (e.g., SD card) with attributes:
  - `type`: Type of storage (e.g., `external`).
  - `sector_size`: Size of each storage sector in bytes.
  - `num_sectors`: Total number of sectors available.
- `<partition>`: Defines a specific partition with attributes:
  - `name`: Partition name (e.g., `master_boot_record`, `APP`).
  - `type`: Type of partition (e.g., `protective_master_boot_record`, `data`).
  - `size`: Size of the partition in bytes or a calculated size (e.g., `APPSIZE`).
  - `filename`: (Optional) Specifies a file associated with the partition.
  - `align_boundary`: (Optional) Ensures the partition starts at a specific byte boundary.
  - `unique_guid`: (Optional) Unique identifier for the partition.

#### Example:
```xml
<partition name="APP" type="data">
    <allocation_policy> sequential </allocation_policy>
    <filesystem_type> basic </filesystem_type>
    <size> APPSIZE </size>
    <filename> APPFILE </filename>
    <unique_guid> APPUUID </unique_guid>
    <description> Contains the root filesystem with kernel and initrd in /boot. </description>
</partition>
```
- `APP`: The main root filesystem partition.
- `APPSIZE`: The size of the partition (usually calculated during flashing).
- `APPFILE`: The file (root filesystem) to be flashed into the partition.
- `APPUUID`: A unique identifier for the partition.

#### Additional Partition Types:
- `master_boot_record`: Contains the MBR for legacy boot compatibility.
- `primary_gpt`/`secondary_gpt`: Contain the GUID partition tables.
- `esp`: EFI System Partition (required for UEFI boot).

---

### General Notes:
- Partition attributes like `allocation_policy` and `align_boundary` ensure proper alignment and allocation on the storage device, which is critical for performance and compatibility.
- Bootloader partition configurations are typically for onboard flash (SPI or eMMC), while rootdisk configurations are for external storage (SD card, USB).
- Ensure filenames in the XML correspond to valid binary files or disk images in the flashing environment.
- Backup existing partition XML files before making modifications.

For further details on the XML structure, consult NVIDIA’s documentation for your Jetson platform.

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --l4t-dir)
      L4T_DIR="$2"
      shift 2
      ;;
    --bootloader-partition-xml)
      BOOTLOADER_PARTITION_XML="$2"
      shift 2
      ;;
    --rootdisk-partition-xml)
      ROOTDISK_PARTITION_XML="$2"
      shift 2
      ;;
    --boot-order-overlay)
      BOOT_ORDER_OVERLAY="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
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
# Convert relative paths to absolute paths
if [ -n "$ROOTDISK_PARTITION_XML" ]; then
  ROOTDISK_PARTITION_XML=$(to_absolute_path "$ROOTDISK_PARTITION_XML")
fi

if [ -n "$BOOTLOADER_PARTITION_XML" ]; then
  BOOTLOADER_PARTITION_XML=$(to_absolute_path "$BOOTLOADER_PARTITION_XML")
fi

if [ -n "$BOOT_ORDER_OVERLAY" ]; then
  BOOT_ORDER_OVERLAY=$(to_absolute_path "$BOOT_ORDER_OVERLAY")
fi

# Step 1: Check or extract L4T folder
if [ -z "$L4T_DIR" ]; then
  echo "Step 1: Specify the location of the tar file"
  read -p "Enter the full path to the tar file (e.g., /path/to/L4T_Image.tar.gz): " IMAGE_SOURCE

  if [ ! -f "$IMAGE_SOURCE" ]; then
    echo "File not found: $IMAGE_SOURCE"
    exit 1
  fi

  L4T_DIR="$(basename "$IMAGE_SOURCE" .tar.gz)"
  echo "L4T Directory to be used: $L4T_DIR"
  if [ $DRY_RUN -eq 0 ]; then
    echo "Extracting image source..."
    cmd="sudo tar xvpf \"$IMAGE_SOURCE\""
    if confirm_command "$cmd"; then
      sudo tar xvpf "$IMAGE_SOURCE" || { echo "Extraction failed"; exit 1; }
    else
      exit 1
    fi
  else
    echo "[Dry-run] Would extract tar: sudo tar xvpf \"$IMAGE_SOURCE\""
    confirm_command "[Dry-run] Would extract tar: sudo tar xvpf \"$IMAGE_SOURCE\""
  fi
fi

# Validate L4T directory
L4T_DIR=$(to_absolute_path "$L4T_DIR")
if [ ! -d "$L4T_DIR" ] && [ $DRY_RUN -eq 0 ]; then
  echo "L4T directory not found: $L4T_DIR"
  exit 1
fi

# Prompt to skip l4t_initrd_flash.sh early
echo "Do you want to skip flashing the root filesystem using l4t_initrd_flash.sh?"
read -p "Skip root filesystem flashing? [y/N]: " skip_rootfs
skip_rootfs=${skip_rootfs,,} # Convert to lowercase
if [[ "$skip_rootfs" == "y" || "$skip_rootfs" == "yes" ]]; then
  SKIP_ROOTFS_FLASH=1
fi

# Step 2: Select USB partition
if [ $SKIP_ROOTFS_FLASH -eq 0 ]; then
  # Step 2: Select USB partition
  echo "Step 2: Select a partition from the available disks and partitions"
  echo "Available partitions:"

  PARTITIONS=($(lsblk -lno NAME,SIZE,TYPE | awk '$3 == "part" {print $1}'))

  if [ ${#PARTITIONS[@]} -eq 0 ]; then
    echo "No partitions available."
    exit 1
  fi

  for i in "${!PARTITIONS[@]}"; do
    PARTITION_NAME="${PARTITIONS[i]}"
    PARTITION_SIZE=$(lsblk -lno SIZE "/dev/$PARTITION_NAME")
    DISK_NAME=$(lsblk -lno PKNAME "/dev/$PARTITION_NAME" | head -n1)
    echo "$((i + 1)): /dev/$PARTITION_NAME - Size: $PARTITION_SIZE (Disk: $DISK_NAME)"
  done

  read -p "Enter the number of the partition to use (e.g., 1): " PARTITION_INDEX
  PARTITION_INDEX=$((PARTITION_INDEX - 1))

  SELECTED_PARTITION="${PARTITIONS[$PARTITION_INDEX]}"

  if [ -z "$SELECTED_PARTITION" ]; then
    echo "Invalid selection."
    exit 1
  fi

  DISK_NAME=$(lsblk -lno PKNAME "/dev/$SELECTED_PARTITION" | head -n1)

  echo "Selected disk: $DISK_NAME"
fi

# Step 3: Validate partition XML files
if [ -z "$BOOTLOADER_PARTITION_XML" ]; then
  echo "The --bootloader-partition-xml argument is required."
  exit 1
fi

if [ -n "$ROOTDISK_PARTITION_XML" ] && [ ! -f "$ROOTDISK_PARTITION_XML" ] && [ $DRY_RUN -eq 0 ]; then
  echo "Rootdisk partition XML not found: $ROOTDISK_PARTITION_XML"
  exit 1
fi

if [ ! -f "$BOOTLOADER_PARTITION_XML" ] && [ $DRY_RUN -eq 0 ]; then
  echo "Bootloader partition XML not found: $BOOTLOADER_PARTITION_XML"
  exit 1
fi

# Step 4: Flash USB device
if [ -n "$ROOTDISK_PARTITION_XML" ]; then
  if [ $SKIP_ROOTFS_FLASH -eq 0 ]; then
    echo "Using l4t_initrd_flash.sh for flashing the USB device to store the rootfs"
    cmd="BOARDID=3701 BOARDSKU=0000 FAB=TS4 ./tools/kernel_flash/l4t_initrd_flash.sh -c $ROOTDISK_PARTITION_XML --external-device sda1 --direct $DISK_NAME jetson-agx-orin-devkit external"
    if confirm_command "$cmd"; then
      if [ $DRY_RUN -eq 0 ]; then
        pushd "${L4T_DIR%/}" > /dev/null
        eval "$cmd" || {
          echo "Rootfs flashing failed. Exiting."
          popd > /dev/null
          exit 1
        }
        popd > /dev/null
      else
        echo "[Dry-run] Would run: (cd ${L4T_DIR%/}/tools/kernel_flash && $cmd)"
      fi
    else
      echo "Skipping rootfs flashing as per user choice."
    fi
  else
    echo "Rootfs flashing skipped."
  fi
else
  echo "Rootdisk partition XML is not provided. Skipping rootfs flashing."
fi

# Step 5: Flash the Jetson bootloader
echo "Using flash.sh to flash the bootloader on to the jetson"
if [ -n "$BOOT_ORDER_OVERLAY" ]; then
  cmd="ADDITIONAL_DTB_OVERLAY=$BOOT_ORDER_OVERLAY ./flash.sh -c $BOOTLOADER_PARTITION_XML jetson-agx-orin-devkit sda1"
else
  cmd="./flash.sh -c $BOOTLOADER_PARTITION_XML jetson-agx-orin-devkit sda1"
fi
if confirm_command "$cmd"; then
  if [ $DRY_RUN -eq 0 ]; then
    pushd "${L4T_DIR%/}" > /dev/null
    eval "$cmd" || {
      echo "Bootloader flash failed. Exiting."
      exit 1
    }
    popd > /dev/null
  else
    echo "[Dry-run] Would run: (cd ${L4T_DIR%/} && $cmd)"
  fi
else
  echo "Skipping bootloader flashing as per user choice"
fi

# Wait for USB flashing to complete if not in dry-run mode
if [ $DRY_RUN -eq 0 ]; then
  echo "USB flashing completed."
fi

# Step 6: Finish
echo "Step 6: Operation completed successfully!"
if [ $DRY_RUN -eq 1 ]; then
  echo "[Dry-run] All operations simulated successfully."
fi
exit 0

