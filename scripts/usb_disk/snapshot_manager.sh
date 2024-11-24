#!/bin/bash

SNAPSHOT_DIR="snapshots"
DRY_RUN=false

# Function to display help
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTION]

This script helps you manage snapshots of partitions using partclone.
It allows you to create, repair, or restore snapshots.

OPTIONS:
  --help                Show this help message and exit.
  --dry-run             Simulate operations without making changes.

HOW IT WORKS:
  1. The script lists all partitions and prompts you to select one.
  2. You can choose to create a new snapshot, repair a partition, or restore a snapshot.
  3. Snapshots are stored in a folder named '$SNAPSHOT_DIR' in the current directory.

REQUIREMENTS:
  - Bash 4.0+.
  - partclone and fsck installed.

EXAMPLES:
  Dry-run to check actions:
    ./$(basename "$0") --dry-run

  Create a snapshot:
    ./$(basename "$0")
      - Select a partition.
      - Choose the 'Create a snapshot' option.

  Restore a snapshot:
    ./$(basename "$0")
      - Select a snapshot and target partition for restoring.

  Repair a partition:
    ./$(basename "$0")
      - Select a partition to run fsck and repair if needed.

EOF
}

# Function to dynamically select from a list
dynamic_menu() {
    local -n options=$1
    local selected=0

    while true; do
        clear
        echo "Available options:"
        for i in "${!options[@]}"; do
            if [ $i -eq $selected ]; then
                echo "> ${options[$i]}"
            else
                echo "  ${options[$i]}"
            fi
        done
        echo ""
        echo "Use arrow keys to navigate, Enter to select, or 'q' to quit."

        read -rsn1 key
        case $key in
            $'\x1b') # Handle arrow keys
                read -rsn2 -t 0.1 key
                if [[ $key == "[A" ]]; then
                    ((selected--))
                    [ $selected -lt 0 ] && selected=$((${#options[@]} - 1))
                elif [[ $key == "[B" ]]; then
                    ((selected++))
                    [ $selected -ge ${#options[@]} ] && selected=0
                fi
                ;;
            '') # Enter
                return $selected
                ;;
            q) # Quit
                echo "Exiting."
                exit 0
                ;;
        esac
    done
}

# Function to list all partitions with additional details
select_partition() {
    echo "Select a target partition by index:"
    partitions=($(lsblk -rno NAME,SIZE,TYPE,MOUNTPOINT | awk '$3 == "part" {print $1 "|" $2 "|" $4}'))
    if [ ${#partitions[@]} -eq 0 ]; then
        echo "No partitions found. Exiting."
        exit 1
    fi
    for i in "${!partitions[@]}"; do
        name=$(echo "${partitions[$i]}" | awk -F"|" '{print $1}')
        size=$(echo "${partitions[$i]}" | awk -F"|" '{print $2}')
        mountpoint=$(echo "${partitions[$i]}" | awk -F"|" '{print $3}')
        if [ -n "$mountpoint" ]; then
            echo "[$i] /dev/$name (${size}) [Mounted at $mountpoint]"
        else
            echo "[$i] /dev/$name (${size}) [Not Mounted]"
        fi
    done
    read -p "Enter the index: " index
    if [[ $index =~ ^[0-9]+$ ]] && [ $index -ge 0 ] && [ $index -lt ${#partitions[@]} ]; then
        selected_partition="/dev/$(echo "${partitions[$index]}" | awk -F"|" '{print $1}')"
        mountpoint=$(echo "${partitions[$index]}" | awk -F"|" '{print $3}')
        if [ -n "$mountpoint" ]; then
            echo "Warning: Selected partition is mounted at $mountpoint."
            read -p "Are you sure you want to continue? (y/N): " confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                echo "Operation canceled."
                exit 1
            fi
        fi
        echo "Selected partition: $selected_partition"
    else
        echo "Invalid selection. Exiting."
        exit 1
    fi
}

# Function to repair a partition
repair_partition() {
    echo "Checking and repairing partition: $selected_partition"
    echo "Unmounting $selected_partition (if mounted)..."
    sudo umount "$selected_partition" 2>/dev/null || true

    # Run fsck to repair the partition
    if $DRY_RUN; then
        echo "[DRY-RUN] Would run: fsck.ext4 -y $selected_partition"
    else
        sudo fsck.ext4 -y "$selected_partition"
        if [ $? -ne 0 ]; then
            echo "Repair failed or additional issues found."
            exit 1
        fi
        echo "Repair complete for $selected_partition."
    fi
}

# Function to create a snapshot
create_snapshot() {
    repair_partition  # Ensure the partition is repaired before snapshotting

    mkdir -p "$SNAPSHOT_DIR"
    read -p "Enter a version or description for the snapshot (e.g., 'v1', 'backup', 'post-update'): " version
    version=${version// /_}  # Replace spaces with underscores for compatibility
    snapshot_file="$SNAPSHOT_DIR/snapshot_$(date +%Y%m%d_%H%M%S)_${version}.img"

    echo "Creating snapshot: $snapshot_file"
    if $DRY_RUN; then
        echo "[DRY-RUN] Would run: partclone.ext4 -c -s $selected_partition -o $snapshot_file -L snapshot_create.log"
    else
        sudo partclone.ext4 -c -s "$selected_partition" -o "$snapshot_file" -L snapshot_create.log
        if [ $? -ne 0 ]; then
            echo "Snapshot creation failed. Check snapshot_create.log for details."
            exit 1
        fi
        echo "Snapshot created at $snapshot_file"
    fi
}

# Function to restore a snapshot
restore_snapshot() {
    if [ ! -d "$SNAPSHOT_DIR" ]; then
        echo "No snapshots directory found. Exiting."
        exit 1
    fi

    mapfile -t snapshots < <(ls -1 "$SNAPSHOT_DIR" | grep .img)
    if [ ${#snapshots[@]} -eq 0 ]; then
        echo "No snapshots found. Exiting."
        exit 1
    fi

    dynamic_menu snapshots
    selected_snapshot="${snapshots[$?]}"
    snapshot_path="$SNAPSHOT_DIR/$selected_snapshot"

    if [ ! -f "$snapshot_path" ]; then
        echo "Error: Selected snapshot file does not exist: $snapshot_path"
        exit 1
    fi

    echo "Select the target partition for restoring:"
    select_partition  # Prompt user to select target partition

    repair_partition  # Ensure the target partition is repaired before restoring

    echo "Restoring snapshot: $snapshot_path to $selected_partition"
    echo "Unmounting $selected_partition (if mounted)..."
    sudo umount "$selected_partition" 2>/dev/null || true

    # Decompress the snapshot if compressed
    if file "$snapshot_path" | grep -q 'gzip compressed'; then
        echo "Decompressing snapshot..."
        decompressed_path="${snapshot_path%.gz}"
        gunzip -c "$snapshot_path" > "$decompressed_path"
        snapshot_path="$decompressed_path"
    fi

    if $DRY_RUN; then
        echo "[DRY-RUN] Would run: partclone.ext4 -r -s $snapshot_path -O $selected_partition -L snapshot_restore.log"
    else
        sudo partclone.ext4 -r -s "$snapshot_path" -O "$selected_partition" -L snapshot_restore.log
        if [ $? -ne 0 ]; then
            echo "Restore failed. Check snapshot_restore.log for details."
            exit 1
        fi
        echo "Restore complete."
    fi
}

# Parse command-line arguments
for arg in "$@"; do
    case $arg in
    --help)
        show_help
        exit 0
        ;;
    --dry-run)
        DRY_RUN=true
        ;;
    *)
        echo "Unknown option: $arg"
        show_help
        exit 1
        ;;
    esac
done

# Ensure script runs as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

# Main script logic
echo "What would you like to do?"
echo "[1] Create a snapshot"
echo "[2] Restore a snapshot"
echo "[3] Repair a partition"
read -p "Enter your choice: " action

case $action in
1)
    echo "Select a partition to create a snapshot:"
    select_partition
    create_snapshot
    ;;
2)
    restore_snapshot
    ;;
3)
    echo "Select a partition to repair:"
    select_partition
    repair_partition
    ;;
*)
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac

