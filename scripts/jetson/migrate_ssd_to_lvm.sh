#!/bin/bash
set -euo pipefail

# === Root check ===
if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)."
  exit 1
fi

# === Configuration ===
PART=/dev/nvme0n1p1              # Original partition
DISK=/dev/nvme0n1                # Whole disk
MOUNT_OLD=/xavier_ssd            # Current mount point
MOUNT_NEW=/mnt/new_data          # Temp mount point
VG_NAME=vg_ssd                   # Volume group name
LV_NAME=lv_data                  # Logical volume name
NEW_PART_NUM=2                   # New partition number for LVM
RESIZE_PCT=40                    # % to shrink existing partition to
DEBUG=0                          # Debug flag

# === Parse arguments ===
for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=1 ;;
  esac
done

pause_step() {
  if [[ "$DEBUG" -eq 1 ]]; then
    echo
    read -rp "Press ENTER to continue..."
  fi
}

# === Check prerequisites ===
echo "[*] Checking prerequisites..."
command -v dumpe2fs >/dev/null || { echo "dumpe2fs not found"; exit 1; }
command -v resize2fs >/dev/null || { echo "resize2fs not found"; exit 1; }
command -v gdisk >/dev/null || { echo "gdisk not found"; exit 1; }
# === LVM tool check ===
for bin in pvcreate vgcreate lvcreate lvdisplay; do
  if ! command -v "$bin" &>/dev/null; then
    echo "❌ Required LVM tool '$bin' is missing. Installing LVM2 (e.g. 'sudo apt install lvm2')."
    apt install -y lvm2
  fi
done
pause_step

# === Step 1: Shrink the filesystem and verify data fits ===
echo "[*] Shrinking filesystem..."
disk_bytes=$(blockdev --getsize64 "$DISK")
target_bytes=$(( disk_bytes * RESIZE_PCT / 100 ))
target_gib=$(( target_bytes / 1024 / 1024 / 1024 ))
used_kb=$(df --output=used "$PART" | tail -n1)
used_bytes=$(( used_kb * 1024 ))

if (( used_bytes >= target_bytes )); then
  echo "❌ ERROR: used space is more than ${RESIZE_PCT}% of total disk. Aborting."
  exit 1
fi
echo "[*] Shrinking filesystem to ${target_gib}G is safe."
pause_step

# === Step 2: Stop services that may use the mount ===
echo "[*] Stopping services that may be using $MOUNT_OLD..."
systemctl stop docker || true
pause_step

# === Step 3: Unmount and shrink filesystem ===
echo "[*] Unmounting and checking filesystem..."
if mountpoint -q "$MOUNT_OLD"; then
  umount -l "$MOUNT_OLD"
else
  echo "[-] $MOUNT_OLD is not mounted, continuing..."
fi
e2fsck -fy "$PART"
echo "[*] Resizing filesystem to ${target_gib}G..."
resize2fs "$PART" "${target_gib}G"
pause_step

# === Step 4: Shrink the partition using gdisk ===
echo "[*] Shrinking partition..."
start_sector=$(gdisk -l "$DISK" | awk '$1 == "1" { print $2 }')
sectors_per_gib=$((1024 * 1024 * 1024 / 512))
new_end_sector=$((start_sector + target_gib * sectors_per_gib - 1))

echo -e "d\n1\nn\n1\n${start_sector}\n+${target_gib}G\nt\n1\n8300\nw\ny\n" | gdisk "$DISK"
partprobe "$DISK"
pause_step

# === Step 5: Create LVM partition in freed space ===
echo "[*] Creating new partition for LVM..."
echo -e "n\n${NEW_PART_NUM}\n\n\nt\n${NEW_PART_NUM}\n8e00\nw\ny\n" | gdisk "$DISK"
partprobe "$DISK"
LVM_PART="${DISK}p${NEW_PART_NUM}"

if sgdisk -p "$DISK" | grep -q "^ *${NEW_PART_NUM} "; then
  echo "[*] Partition number $NEW_PART_NUM already exists on $DISK, skipping creation."
else
  echo "[*] Creating partition $NEW_PART_NUM for LVM..."
  start_sector=$(sgdisk -F "$DISK")
  sgdisk -n "${NEW_PART_NUM}:${start_sector}:0" -t "${NEW_PART_NUM}:8e00" "$DISK"
  partprobe "$DISK"
fi
pause_step

# === Step 6: Set up LVM ===
echo "[*] Initializing LVM setup..."
pvcreate "$LVM_PART"
vgcreate "$VG_NAME" "$LVM_PART"
lvcreate -l 100%FREE -n "$LV_NAME" "$VG_NAME"
mkfs.ext4 "/dev/${VG_NAME}/${LV_NAME}"
pause_step

# === Step 7: Copy data to LVM ===
mkdir -p "$MOUNT_NEW"
mount "/dev/${VG_NAME}/${LV_NAME}" "$MOUNT_NEW"
echo "[*] Copying data to LVM volume..."
rsync -aHAXv "$MOUNT_OLD/" "$MOUNT_NEW/"
pause_step

# === Step 8: Swap mounts ===
echo "[*] Swapping mounts to point to LVM..."
if mountpoint -q "$MOUNT_OLD"; then
  umount "$MOUNT_OLD"
else
  echo "[-] $MOUNT_OLD is not mounted, skipping unmount."
fi

umount "$MOUNT_NEW"
mount "/dev/${VG_NAME}/${LV_NAME}" "$MOUNT_OLD"
pause_step

# === Step 9: Update fstab ===
echo "[*] Updating /etc/fstab..."
uuid=$(blkid -s UUID -o value "/dev/${VG_NAME}/${LV_NAME}")
cp /etc/fstab /etc/fstab.bak
sed -i "\|[[:space:]]${MOUNT_OLD}[[:space:]]|d" /etc/fstab
echo "UUID=$uuid $MOUNT_OLD ext4 defaults,nofail 0 2" >> /etc/fstab

# === Step 10: Expand LVM to use the entire disk ===
echo "[*] Expanding LVM to use the entire disk..."

if mountpoint -q "$MOUNT_OLD"; then
  echo "[-] Unmounting $MOUNT_OLD..."
  umount "$MOUNT_OLD"
fi

# Ensure partition 1 (/dev/nvme0n1p1) is LVM-compatible
echo "[*] Changing partition 1 (/dev/nvme0n1p1) to LVM type..."
echo -e "t\n1\n8e00\nw\ny\n" | gdisk /dev/nvme0n1
partprobe "$DISK"
sleep 2

echo "[*] Changing partition 2 (/dev/nvme0n1p2) to LVM type..."
echo -e "t\n2\n8e00\nw\ny\n" | gdisk /dev/nvme0n1
partprobe "$DISK"
sleep 2

# Add /dev/nvme0n1p1 to the existing volume group
echo "[*] Adding /dev/nvme0n1p1 to the volume group $VG_NAME..."
# nvextend outputs to stdou so we need || true so we don't "fail"
yes | vgextend -f "$VG_NAME" /dev/nvme0n1p1 || true
sleep 2

# Resize the logical volume to use all free space in the volume group
echo "[*] Extending logical volume $LV_NAME to use all available space..."
lvextend -l +100%FREE "/dev/${VG_NAME}/${LV_NAME}"
sleep 2

# Resize the filesystem to use the expanded logical volume
echo "[*] Resizing filesystem to use the expanded logical volume..."
resize2fs "/dev/${VG_NAME}/${LV_NAME}"
e2fsck -fy "/dev/${VG_NAME}/${LV_NAME}"

# Remount the LVM
mount "/dev/${VG_NAME}/${LV_NAME}" "$MOUNT_OLD"

echo
echo "[✓] LVM now spans the entire disk. Logical volume $LV_NAME is using the full space at $MOUNT_OLD."

