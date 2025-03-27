#!/bin/bash
set -euo pipefail

# === Configuration ===
DISK=/dev/nvme0n1                # Disk to create partition on
MOUNT_POINT=/xavier_ssd           # Mount point
FSTAB_FILE=/etc/fstab             # fstab file location

# === Ensure the disk is not in use ===
echo "[*] Unmounting any existing mounts..."
umount "$MOUNT_POINT" || true
umount /dev/nvme0n1* || true

# === Step 1: Delete all existing partitions ===
echo "[*] Deleting all existing partitions on $DISK..."
parted "$DISK" mklabel gpt  # Creates a new GPT partition table

# === Step 2: Create a new partition ===
echo "[*] Creating a new partition /dev/nvme0n1p1 as ext4..."
parted -a optimal "$DISK" mkpart primary ext4 0% 100%  # Creates a partition that spans the entire disk

# === Step 3: Format the partition with ext4 ===
echo "[*] Formatting /dev/nvme0n1p1 as ext4..."
mkfs.ext4 /dev/nvme0n1p1

# === Step 4: Mount the partition ===
echo "[*] Mounting /dev/nvme0n1p1 to $MOUNT_POINT..."
mkdir -p "$MOUNT_POINT"
mount /dev/nvme0n1p1 "$MOUNT_POINT"

# === Step 5: Create a test file to track movement ===
echo "[*] Creating test file inside $MOUNT_POINT..."
touch "$MOUNT_POINT/text.txt"
echo "This is a test file to track movement." > "$MOUNT_POINT/test.txt"

# === Step 6: Update /etc/fstab to mount the partition at boot ===
echo "[*] Updating /etc/fstab..."
UUID=$(blkid -s UUID -o value /dev/nvme0n1p1)
cp /etc/fstab /etc/fstab.bak
echo -e "/dev/root            /                     ext4           defaults                                     0 1" > "$FSTAB_FILE"
echo "UUID=$UUID $MOUNT_POINT ext4 nofail 0 0" >> "$FSTAB_FILE"

# === Step 7: Mount all filesystems from /etc/fstab ===
echo "[*] Running mount -a to mount all filesystems listed in /etc/fstab..."
mount -a

# === Verify ===
echo "[*] Verifying the changes..."

# Verify that the partition is mounted
lsblk

# Check if the test file exists
if [ -f "$MOUNT_POINT/test.txt" ]; then
    echo "[✓] Test file created successfully at $MOUNT_POINT/test.txt"
else
    echo "❌ Test file creation failed."
fi

echo "[✓] The disk has been hard reset and the original partition and fstab state recreated."

