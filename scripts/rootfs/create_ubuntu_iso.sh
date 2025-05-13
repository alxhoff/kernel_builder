#!/usr/bin/env bash
set -euo pipefail

UBUNTU_VERSION="20.04.6"
ISO_NAME="ubuntu-${UBUNTU_VERSION}-desktop-amd64.iso"
ISO_URL="https://releases.ubuntu.com/${UBUNTU_VERSION}/${ISO_NAME}"
WORK_DIR="$PWD/ubuntu_iso_work"
MOUNT_DIR="$WORK_DIR/iso_mount"
EXTRACT_DIR="$WORK_DIR/extracted_iso"
SQUASHFS_DIR="$WORK_DIR/squashfs-root"
EDIT_DIR="$WORK_DIR/edit"
NEW_ISO="$PWD/custom-ubuntu-${UBUNTU_VERSION}-desktop.iso"
ARCHIVE_NAME="jetson_bsp.tar.xz"
CHROOT_DIR="$EDIT_DIR"

if [[ "$EUID" -ne 0 ]]; then
    echo "❌ This script must be run as root. Please use sudo."
    exit 1
fi

# --- Ensure required packages are installed on Arch Linux host ---
echo "[*] Installing required host packages..."
pacman -S --needed --noconfirm \
    wget rsync squashfs-tools xorriso dosfstools arch-install-scripts fuse2 util-linux

# 1. Download Ubuntu ISO
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
if [[ ! -f "$ISO_NAME" ]]; then
    echo "[*] Downloading Ubuntu Desktop $UBUNTU_VERSION ISO..."
    wget -q --show-progress "$ISO_URL"
fi

# 2. Mount and extract ISO
echo "[*] Mounting original ISO..."
mkdir -p "$MOUNT_DIR"
if mountpoint -q "$MOUNT_DIR"; then
    echo "[*] Unmounting existing ISO mount..."
    umount "$MOUNT_DIR"
fi
mount -o loop "$ISO_NAME" "$MOUNT_DIR"

echo "[*] Copying ISO contents..."
mkdir -p "$EXTRACT_DIR"
rsync -a --exclude=/casper/filesystem.squashfs "$MOUNT_DIR/" "$EXTRACT_DIR"

echo "[*] Extracting squashfs..."
rm -rf "$SQUASHFS_DIR"
unsquashfs -d "$SQUASHFS_DIR" "$MOUNT_DIR/casper/filesystem.squashfs"

echo "[*] Unmounting ISO..."
umount "$MOUNT_DIR"

# 3. Prepare chroot
echo "[*] Setting up chroot environment..."
rm -rf "$EDIT_DIR"
cp -a "$SQUASHFS_DIR" "$EDIT_DIR"

# 4. Write customization script
cat <<'EOF' > "$CHROOT_DIR/chroot_setup.sh"
#!/bin/bash
set -e
apt update
add-apt-repository universe
apt update
apt install -y sudo curl wget python3-pip unzip git usbutils libxml2-utils binutils xz-utils dpkg-dev udev
pip3 install gdown pyyaml

cd /root
ARCHIVE_NAME="jetson_bsp.tar.xz"
gdown --fuzzy 'https://drive.google.com/uc?id=17npAsBctuCWB7PHwYnPJXW-8GVQvMKCg' -O $ARCHIVE_NAME
mkdir -p jetson_bsp
tar -xf $ARCHIVE_NAME -C jetson_bsp --strip-components=1
rm -f $ARCHIVE_NAME
echo "[*] Chroot customization completed"
EOF

chmod +x "$CHROOT_DIR/chroot_setup.sh"

echo "[*] Running chroot customization script..."
manjaro-chroot "$CHROOT_DIR" /chroot_setup.sh

echo "🚪 Now entering chroot interactively. Type 'exit' when done."
manjaro-chroot "$CHROOT_DIR" /bin/bash

rm -f "$CHROOT_DIR/chroot_setup.sh"

# 6. Rebuild squashfs
echo "[*] Repacking filesystem..."
mksquashfs "$EDIT_DIR" "$EXTRACT_DIR/casper/filesystem.squashfs" -noappend

# 6.1 Update filesystem.size
echo "[*] Updating filesystem.size..."
printf $(du -sx --block-size=1 "$EDIT_DIR" | cut -f1) > "$EXTRACT_DIR/casper/filesystem.size"

# 6.2 Regenerate manifest
echo "[*] Regenerating filesystem.manifest..."
manjaro-chroot "$EDIT_DIR" dpkg-query -W --showformat='${Package} ${Version}\n' > "$EXTRACT_DIR/casper/filesystem.manifest"

# 6.3 Generate filesystem.manifest-remove
echo "[*] Creating filesystem.manifest-remove..."
cp "$EXTRACT_DIR/casper/filesystem.manifest" "$EXTRACT_DIR/casper/filesystem.manifest-remove"
sed -i '/ubiquity/d;/casper/d' "$EXTRACT_DIR/casper/filesystem.manifest-remove"

# 6.4 Update md5sum.txt
echo "[*] Updating md5sum.txt..."
cd "$EXTRACT_DIR"
find . -type f -print0 | xargs -0 md5sum | grep -v isolinux/boot.cat > md5sum.txt

# 6. Build new ISO
echo "[*] Generating ISO..."
cd "$EXTRACT_DIR"
xorriso -as mkisofs \
  -r -V "CustomUbuntu" \
  -J -l -iso-level 3 \
  -b isolinux/isolinux.bin \
  -c isolinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -o "$NEW_ISO" .

echo "✅ Done. ISO created at: $NEW_ISO"

# 7. Prompt for writing to USB
read -rp "Do you want to write the ISO to a USB drive now? [y/N]: " confirm_dd
if [[ "$confirm_dd" =~ ^[Yy]$ ]]; then
    lsblk
    read -rp "Enter the device name to write to (e.g., sda): " dev
    if [[ -b "/dev/$dev" ]]; then
        read -rp "Are you absolutely sure? This will erase /dev/$dev [yes/NO]: " double_check
        if [[ "$double_check" == "yes" ]]; then
            dd if="$NEW_ISO" of="/dev/$dev" bs=4M status=progress oflag=sync
            echo "✅ ISO written to /dev/$dev"
        else
            echo "❌ Aborted."
        fi
    else
        echo "❌ Invalid device: /dev/$dev"
    fi
else
    echo "ℹ️ Skipping ISO write."
fi

