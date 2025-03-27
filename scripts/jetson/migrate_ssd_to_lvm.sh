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

# === Step 1: Calculate shrink size and verify data fits ===
echo "[*] Calculating safe shrink size..."
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

# === Step: Stop services that may use the mount ===
echo "[*] Stopping services that may be using $MOUNT_OLD..."

# Stop Docker to release /xavier_ssd
systemctl stop docker || true

# Optional: stop anything else here
# systemctl stop some-other-service
# killall some-process

pause_step

# === Step 2: Unmount and shrink filesystem ===
echo "[*] Unmounting and checking filesystem..."
echo "[*] Unmounting $MOUNT_OLD if mounted..."
if mountpoint -q "$MOUNT_OLD"; then
  umount -l "$MOUNT_OLD"
else
  echo "[-] $MOUNT_OLD is not mounted, continuing..."
fi
e2fsck -f "$PART"
echo "[*] Resizing filesystem to ${target_gib}G..."
resize2fs "$PART" "${target_gib}G"
pause_step

# === Step 3: Shrink the partition using gdisk ===
echo "[*] Shrinking partition..."
start_sector=$(gdisk -l "$DISK" | awk '$1 == "1" { print $2 }')
sectors_per_gib=$((1024 * 1024 * 1024 / 512))
new_end_sector=$((start_sector + target_gib * sectors_per_gib - 1))

echo -e "d\n1\nn\n1\n${start_sector}\n+${target_gib}G\nt\n1\n8300\nw\ny\n" | gdisk "$DISK"
partprobe "$DISK"
pause_step

# === Step 4: Mount back and verify ===
echo "[*] Remounting and verifying resized partition..."
mount "$PART" "$MOUNT_OLD"
df -h "$MOUNT_OLD"
pause_step

# === Step 5: Create LVM partition in freed space ===
echo "[*] Creating new partition for LVM..."
echo -e "n\n${NEW_PART_NUM}\n\n\nt\n${NEW_PART_NUM}\n8e00\nw\ny\n" | gdisk "$DISK"
partprobe "$DISK"

LVM_PART="${DISK}p${NEW_PART_NUM}"

# Check if partition with that number exists already
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
umount "$MOUNT_OLD"
umount "$MOUNT_NEW"
mount "/dev/${VG_NAME}/${LV_NAME}" "$MOUNT_OLD"
pause_step

# === Step 9: Update fstab ===
echo "[*] Updating /etc/fstab..."
uuid=$(blkid -s UUID -o value "/dev/${VG_NAME}/${LV_NAME}")
cp /etc/fstab /etc/fstab.bak
sed -i "\|[[:space:]]${MOUNT_OLD}[[:space:]]|d" /etc/fstab
echo "UUID=$uuid $MOUNT_OLD ext4 defaults,nofail 0 2" >> /etc/fstab

echo
echo "[✓] Migration complete. LVM is now mounted at $MOUNT_OLD."

