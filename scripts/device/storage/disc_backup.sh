#!/usr/bin/env bash
# Disk Backup Utility: Create and restore compressed sparse images of a disk via sparse dd+gzip.
# Shrinks ext4 filesystem to minimum, adjusts partition table, then dumps only the used blocks and saves GPT after shrink.
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 <command> [options]

Commands:
  create   Create a compressed sparse disk image of a selected disk
           --output <path>   Path to write the .img.gz file

  restore  Restore a compressed disk image onto a selected target disk
           --input <path>    Path to read the .img.gz file

Global options:
  -h, --help            Show this help message and exit

Examples:
  $0 create --output ~/usb_backup/disk.img.gz
  $0 restore --input  ~/usb_backup/disk.img.gz
EOF
  exit 1
}

# Show help
if [[ $# -eq 0 ]] || [[ "$1" =~ ^(-h|--help)$ ]]; then
  usage
fi

mode=$1; shift

# Function to list disks for manual selection
list_disks() {
  echo "Available disks:"
  lsblk -dnpo NAME,SIZE,MODEL | awk '{printf "%s — %s — %s\n", $1, $2, substr($0, index($0,$3))}'
}

case "$mode" in
  create)
    # Validate
    [[ $# -eq 2 && $1 == --output ]] || usage
    output=$2
    backup_dir=$(dirname "$output")

    # Select source disk
    list_disks
    read -rp "Enter source disk (e.g. /dev/sda): " source_disk
    [[ -b "$source_disk" ]] || { echo "Invalid disk: $source_disk" >&2; exit 1; }
    part="${source_disk}2"  # assumes root on partition 2

    echo "[+] Saving partition layout to $backup_dir/partitions.txt"
    mkdir -p "$backup_dir"
    sudo parted -ms "$source_disk" unit B print > "$backup_dir/partitions.txt"

    echo "[+] Shrinking filesystem to minimum on $part"
    sudo umount "$part" || true
    sudo e2fsck -f "$part"
    sudo resize2fs -M "$part"

    echo "[+] Calculating filesystem size"
    BC=$(sudo tune2fs -l "$part" | awk '/Block count:/ {print $3}')
    BSZ=$(sudo tune2fs -l "$part" | awk '/Block size:/  {print $3}')
    FS_BYTES=$(( BC * BSZ ))

    echo "[+] Adjusting partition table to match filesystem"
    PART_START=$(sudo parted -ms "$source_disk" unit B print | awk -F: '$1==2 {print $2}' | sed 's/B$//')
    NEW_END=$(( PART_START + FS_BYTES ))
    sudo parted -s "$source_disk" unit B resizepart 2 "$NEW_END" || true

    echo "[+] Preparing to dump $FS_BYTES bytes from $source_disk"
    BS=4M
    BB=$((4 * 1024 * 1024))
    COUNT=$(( (FS_BYTES + BB - 1) / BB ))

    echo "[+] Dumping $COUNT blocks of size $BS from $source_disk into sparse gzip"
    sudo dd if="$source_disk" bs="$BS" count="$COUNT" conv=sparse status=progress \
      | gzip -1 > "$output"

    echo "[+] Backup saved to $output"
    ;;

  restore)
    # Validate
    [[ $# -eq 2 && $1 == --input ]] || usage
    input=$2
    backup_dir=$(dirname "$input")

    # Select target disk
    list_disks
    read -rp "Enter target disk (e.g. /dev/sdb): " target_disk
    [[ -b "$target_disk" ]] || { echo "Invalid disk: $target_disk" >&2; exit 1; }

    echo "[+] Recreating partition table on $target_disk"
    sudo parted -s "$target_disk" mklabel gpt
    while IFS=: read -r num start end fstype name flags; do
      # skip header lines (not starting with digit)
      if ! [[ "$num" =~ ^[0-9]+$ ]]; then continue; fi
      # strip trailing B
      s=${start%B}
      e=${end%B}
      echo "    -> Partition $num: $fstype from $s to $e"
      sudo parted -s "$target_disk" "mkpart" primary "$fstype" ${s}B ${e}B
      if [[ "$flags" == *"boot"* ]]; then
        sudo parted -s "$target_disk" set $num boot on
      fi
      sudo parted -s "$target_disk" name $num "$name"
    done < "$backup_dir/partitions.txt"

    echo "[+] Restoring data from $input to $target_disk"
    gunzip -c "$input" | sudo dd of="$target_disk" bs=4M iflag=fullblock status=progress

    echo "[+] Refreshing partition table"
    sudo partprobe "$target_disk"

    echo "[+] Restore complete on $target_disk"
    ;;

  *)
    echo "Unknown command: $mode" >&2
    usage
    ;;
esac
  create)
    # Validate
    [[ $# -eq 2 && $1 == --output ]] || usage
    output=$2
    backup_dir=$(dirname "$output")

    # Select source disk
    list_disks
    read -rp "Enter source disk (e.g. /dev/sda): " source_disk
    [[ -b "$source_disk" ]] || { echo "Invalid disk: $source_disk" >&2; exit 1; }
    part="${source_disk}2"  # assumes root on partition 2

    echo "[+] Shrinking filesystem to minimum on $part"
    sudo umount "$part" || true
    sudo e2fsck -f "$part"
    sudo resize2fs -M "$part"

    echo "[+] Calculating filesystem size"
    BC=$(sudo tune2fs -l "$part" | awk '/Block count:/ {print $3}')
    BSZ=$(sudo tune2fs -l "$part" | awk '/Block size:/  {print $3}')
    FS_BYTES=$(( BC * BSZ ))

    echo "[+] Adjusting partition table to match filesystem"
    PART_START=$(sudo parted -ms "$source_disk" unit B print | awk -F: '$1==2 {print $2}' | sed 's/B$//')
    NEW_END=$(( PART_START + FS_BYTES ))
    sudo parted -s "$source_disk" unit B resizepart 2 "$NEW_END" || true

    echo "[+] Backing up GPT table after shrink to $backup_dir/table.gpt"
    mkdir -p "$backup_dir"
    sudo sgdisk --backup="$backup_dir/table.gpt" "$source_disk"

    echo "[+] Preparing to dump $FS_BYTES bytes from $source_disk"
    BS=4M
    BB=$((4 * 1024 * 1024))
    COUNT=$(( (FS_BYTES + BB - 1) / BB ))

    echo "[+] Dumping $COUNT blocks of size $BS from $source_disk into sparse gzip"
    sudo dd if="$source_disk" bs="$BS" count="$COUNT" conv=sparse status=progress \
      | gzip -1 > "$output"

    echo "[+] Backup saved to $output"
    ;;

  restore)
    # Validate
    [[ $# -eq 2 && $1 == --input ]] || usage
    input=$2
    backup_dir=$(dirname "$input")

    # Select target disk
    list_disks
    read -rp "Enter target disk (e.g. /dev/sdb): " target_disk
    [[ -b "$target_disk" ]] || { echo "Invalid disk: $target_disk" >&2; exit 1; }

    echo "[+] Restoring GPT table from $backup_dir/table.gpt to $target_disk"
    sudo sgdisk --load-backup="$backup_dir/table.gpt" "$target_disk"

    echo "[+] Restoring data from $input to $target_disk"
    gunzip -c "$input" | sudo dd of="$target_disk" bs=4M iflag=fullblock status=progress

    echo "[+] Restore complete on $target_disk"
    ;;

  *)
    echo "Unknown command: $mode" >&2
    usage
    ;;
esac

