#!/bin/bash

# Script to clean up compiled kernel modules across all kernels in the 'kernels' directory.
# Usage: ./cleanup_all_kernel_builds.sh [--dry-run]
# Arguments:
#   --dry-run    Optional argument to simulate the cleanup without deleting anything

# Set the base kernels directory
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
KERNELS_DIR="$SCRIPT_DIR/kernels"

# Default is not a dry run
DRY_RUN=false

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
    shift
done

echo "Starting cleanup of compiled kernel modules for all kernels in $KERNELS_DIR"

# Iterate over all kernels in the kernels directory
for KERNEL in "$KERNELS_DIR"/*; do
    if [ -d "$KERNEL" ]; then
        KERNEL_NAME=$(basename "$KERNEL")
        MODULES_BASE_PATH="$KERNEL/modules/lib/modules"

        echo "Processing kernel: $KERNEL_NAME"

        # Check if the modules base directory exists
        if [ -d "$MODULES_BASE_PATH" ]; then
            # Iterate over each version directory inside the modules path
            for VERSION_DIR in "$MODULES_BASE_PATH"/*; do
                if [ -d "$VERSION_DIR" ]; then
                    echo "Deleting kernel version directory: $VERSION_DIR"
                    if [ "$DRY_RUN" == false ]; then
                        rm -rf "$VERSION_DIR"
                    else
                        echo "[Dry-run] Would delete: $VERSION_DIR"
                    fi
                fi
            done
        else
            echo "Modules directory not found: $MODULES_BASE_PATH. Skipping cleanup for $KERNEL_NAME."
        fi
    fi
done

echo "Kernel build cleanup complete for all kernels."

