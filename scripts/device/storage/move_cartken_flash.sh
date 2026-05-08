#!/bin/bash
set -euo pipefail

show_help() {
    echo "Usage: $0 [--output <destination_path>] [--auto] [--mount]"
    echo ""
    echo "Copies /mnt/cartken_flash to the specified destination using rsync,"
    echo "preserving all permissions, ownership, and attributes."
    echo ""
    echo "Options:"
    echo "  --output <path>   Manually specify the target path"
    echo "  --auto            Mount a detected root partition to /mnt2 and copy to /home/<user>/cartken_flash"
    echo "  --mount           Like --auto, but only mounts and reports output path (no copy)"
    echo "  -h, --help        Show this help message"
}

if [[ "$EUID" -ne 0 ]]; then
    echo "❌ This script must be run with sudo or as root."
    exit 1
fi

OUTPUT=""
AUTO=false
MOUNT_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            OUTPUT="$2"
            shift 2
            ;;
        --auto)
            AUTO=true
            shift
            ;;
        --mount)
            MOUNT_ONLY=true
            shift
            ;;
        --help|-h)
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

if $AUTO || $MOUNT_ONLY; then
    mkdir -p /mnt2
    echo "[*] Scanning for unmounted potential root partitions..."

    mapfile -t CANDIDATES < <(
        lsblk -rpno NAME,MOUNTPOINT | while read -r dev mnt; do
            [[ -n "$mnt" ]] && continue
            fstype=$(blkid -s TYPE -o value "$dev" 2>/dev/null)
            if [[ "$fstype" =~ ^(ext4|xfs|btrfs)$ ]]; then
                echo "$dev"
            fi
        done
    )

    if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
        echo "❌ No suitable unmounted Linux root partitions found."
        exit 1
    fi

    echo "Available partitions:"
    for i in "${!CANDIDATES[@]}"; do
        echo "  [$i] ${CANDIDATES[$i]}"
    done

    read -rp "Select a partition to mount to /mnt2: " IDX

    if ! [[ "$IDX" =~ ^[0-9]+$ ]] || (( IDX < 0 || IDX >= ${#CANDIDATES[@]} )); then
        echo "❌ Invalid selection"
        exit 1
    fi

    PART="${CANDIDATES[$IDX]}"
    echo "[*] Mounting $PART to /mnt2..."
    mount "$PART" /mnt2

    USER_HOME_BASE="/mnt2/home"
    if [[ ! -d "$USER_HOME_BASE" ]]; then
        echo "❌ No /home directory found on mounted system."
        exit 1
    fi

    USER_DIR=$(find "$USER_HOME_BASE" -mindepth 1 -maxdepth 1 -type d | head -n 1)

    if [[ -z "$USER_DIR" ]]; then
        echo "❌ No user directory found under /home"
        exit 1
    fi

    USERNAME=$(basename "$USER_DIR")
    OUTPUT="$USER_HOME_BASE/$USERNAME"
    echo "[*] Detected user: $USERNAME"
    echo "[*] Output path will be: $OUTPUT"

    if $MOUNT_ONLY; then
        echo "✅ Partition mounted. No copy performed."
        exit 0
    fi
fi

if [[ -z "$OUTPUT" ]]; then
    echo "❌ Error: --output is required unless --auto or --mount is used"
    show_help
    exit 1
fi

echo "[*] Copying /mnt/cartken_flash to $OUTPUT..."
rsync -aAX /mnt/cartken_flash "$OUTPUT"
echo "✅ Copy complete."


