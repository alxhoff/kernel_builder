#!/bin/bash

# Script to clean up compiled kernel modules, images, and DTB files across all kernels in the 'kernels' directory.
# Usage: ./cleanup_all_kernel_builds.sh [--dry-run] [--interactive] [--help]
# Arguments:
#   --dry-run      Optional argument to simulate the cleanup without deleting anything
#   --interactive  Optional argument to prompt for confirmation before each deletion
#   --help         Show detailed help information with examples

# Set the base kernels directory
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
KERNELS_DIR="$SCRIPT_DIR/../../kernels"

# Default values
DRY_RUN=false
INTERACTIVE=false

# Function to display help
show_help() {
    echo "Usage: ./cleanup_all_kernel_builds.sh [OPTIONS]"
    echo
    echo "Options:"
    echo "  --dry-run       Simulate the cleanup process without deleting anything."
    echo "                  This is useful to preview what files and directories would be affected."
    echo
    echo "  --interactive   Prompt for confirmation before deleting each kernel version or image."
    echo "                  The script will ask you whether to delete specific items."
    echo
    echo "  --help          Display this help message and exit."
    echo
    echo "Examples:"
    echo "  ./cleanup_all_kernel_builds.sh"
    echo "      Perform a cleanup of kernel builds without prompting and deletes files directly."
    echo
    echo "  ./cleanup_all_kernel_builds.sh --dry-run"
    echo "      Show what would be deleted without actually deleting anything."
    echo
    echo "  ./cleanup_all_kernel_builds.sh --interactive"
    echo "      Prompt for confirmation before deleting each kernel version or image."
    echo
    echo "  ./cleanup_all_kernel_builds.sh --dry-run --interactive"
    echo "      Simulate the cleanup process and ask for confirmation at each step."
    exit 0
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            ;;
        --interactive)
            INTERACTIVE=true
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Use --help for more information."
            exit 1
            ;;
    esac
    shift
done

echo "Starting cleanup of compiled kernel modules, images, and DTB files in $KERNELS_DIR..."

# Iterate over all kernels in the kernels directory
for KERNEL in "$KERNELS_DIR"/*; do
    if [ -d "$KERNEL" ]; then
        KERNEL_NAME=$(basename "$KERNEL")
        MODULES_BASE_PATH="$KERNEL/modules/lib/modules"
        BOOT_DIR="$KERNEL/modules/boot"

        echo -e "\nProcessing kernel: $KERNEL_NAME"

        # Gather versions and their matching kernel images and DTB files
        declare -A KERNEL_IMAGE_MAP
        IMAGE_FILES=()
        DTB_FILES=()

        # Track processed images and DTBs
        PROCESSED_IMAGES=()
        PROCESSED_DTBS=()

        # Check for boot images and map to corresponding local versions
        if [ -d "$BOOT_DIR" ]; then
            for IMAGE in "$BOOT_DIR"/Image*; do
                if [ -f "$IMAGE" ]; then
                    IMAGE_FILES+=("$IMAGE")
                    IMAGE_NAME=$(basename "$IMAGE")

                    # Extract kernel version using "strings" and "grep"
                    KERNEL_VERSION=$(strings "$IMAGE" | grep -oP "Linux version \K[0-9\.]+[^\s]*")
                    LOCALVERSION="${KERNEL_VERSION#5.10.120}"

                    # Check if LOCALVERSION is empty, then assign it as default
                    if [ -z "$LOCALVERSION" ]; then
                        LOCALVERSION="default"
                    fi

                    # Add to the map
                    KERNEL_IMAGE_MAP["$LOCALVERSION"]="$IMAGE"
                fi
            done

            # Check for DTB files with the same localversion
            for DTB in "$BOOT_DIR"/tegra234-p3701-0000-p3737-0000*.dtb; do
                if [ -f "$DTB" ]; then
                    DTB_FILES+=("$DTB")
                fi
            done
        fi

        # Clean up compiled kernel version modules
        if [ -d "$MODULES_BASE_PATH" ]; then
            for VERSION_DIR in "$MODULES_BASE_PATH"/*; do
                if [ -d "$VERSION_DIR" ]; then
                    VERSION_NAME=$(basename "$VERSION_DIR")
                    LOCALVERSION="${VERSION_NAME#5.10.120}" # Extract the local version part

                    REMOVE=true
                    IMAGE_TO_DELETE=${KERNEL_IMAGE_MAP[$LOCALVERSION]}
                    DTB_TO_DELETE="$BOOT_DIR/tegra234-p3701-0000-p3737-0000${LOCALVERSION}.dtb"

                    # If interactive, prompt the user
                    if [ "$INTERACTIVE" == true ]; then
                        if [ -n "$IMAGE_TO_DELETE" ]; then
                            echo -e "\n[LOCALVERSION: $LOCALVERSION]"
                            echo "Compiled Kernel Version Modules: $VERSION_NAME"
                            echo "Image: $IMAGE_TO_DELETE"
                            echo "DTB: $DTB_TO_DELETE"
                            read -p "Delete kernel version, image, and dtb? (default yes) [Y/n]: " CONFIRM
                        else
                            echo -e "\n[LOCALVERSION: $LOCALVERSION]"
                            echo "Compiled Kernel Version Modules: $VERSION_NAME"
                            read -p "Delete kernel version? (default yes) [Y/n]: " CONFIRM
                        fi
                        case "$CONFIRM" in
                            [nN][oO]|[nN]) REMOVE=false ;;
                            *) REMOVE=true ;; # Default to yes
                        esac
                    fi

                    # Proceed with deletion if confirmed
                    if [ "$REMOVE" == true ]; then
                        if [ "$DRY_RUN" == true ]; then
                            echo "[Dry-run] Would delete kernel version: $VERSION_NAME"
                            if [ -n "$IMAGE_TO_DELETE" ]; then
                                echo "[Dry-run] Would delete image: $(basename "$IMAGE_TO_DELETE")"
                                PROCESSED_IMAGES+=("$IMAGE_TO_DELETE")
                            fi
                            if [ -f "$DTB_TO_DELETE" ]; then
                                echo "[Dry-run] Would delete DTB: $(basename "$DTB_TO_DELETE")"
                                PROCESSED_DTBS+=("$DTB_TO_DELETE")
                            fi
                        else
                            echo "Deleting kernel version: $VERSION_NAME"
                            rm -rf "$VERSION_DIR"
                            if [ -n "$IMAGE_TO_DELETE" ]; then
                                echo "Deleting image: $(basename "$IMAGE_TO_DELETE")"
                                rm -f "$IMAGE_TO_DELETE"
                                PROCESSED_IMAGES+=("$IMAGE_TO_DELETE")
                            fi
                            if [ -f "$DTB_TO_DELETE" ]; then
                                echo "Deleting DTB: $(basename "$DTB_TO_DELETE")"
                                rm -f "$DTB_TO_DELETE"
                                PROCESSED_DTBS+=("$DTB_TO_DELETE")
                            fi
                        fi
                    else
                        echo "Skipped: $VERSION_NAME"
                        if [ -n "$IMAGE_TO_DELETE" ]; then
                            echo "Skipped: $(basename "$IMAGE_TO_DELETE")"
                            PROCESSED_IMAGES+=("$IMAGE_TO_DELETE")
                        fi
                        if [ -f "$DTB_TO_DELETE" ]; then
                            echo "Skipped: $(basename "$DTB_TO_DELETE")"
                            PROCESSED_DTBS+=("$DTB_TO_DELETE")
                        fi
                    fi
                fi
            done
        else
            echo "No modules directory found for: $KERNEL_NAME"
        fi

        # Clean up any orphan kernel images and DTBs (images and DTBs without matching kernel versions)
        for IMAGE in "${IMAGE_FILES[@]}"; do
            # Skip images that were already processed (either deleted or marked as skipped)
            if [[ " ${PROCESSED_IMAGES[@]} " =~ " ${IMAGE} " ]]; then
                continue
            fi

            IMAGE_NAME=$(basename "$IMAGE")
            LOCALVERSION=""

            # Extract LOCALVERSION from image name if available
            if [[ $IMAGE_NAME =~ Image\.(.*) ]]; then
                LOCALVERSION="${BASH_REMATCH[1]}"
            else
                LOCALVERSION="default"
            fi

            REMOVE=true

            # If interactive, prompt the user
            if [ "$INTERACTIVE" == true ]; then
                echo -e "\n[LOCALVERSION: $LOCALVERSION]"
                echo "Orphan image: $IMAGE_NAME"
                read -p "Delete orphan kernel image? (default yes) [Y/n]: " CONFIRM
                case "$CONFIRM" in
                    [nN][oO]|[nN]) REMOVE=false ;;
                    *) REMOVE=true ;; # Default to yes
                esac
            fi

            # Proceed with deletion if confirmed
            if [ "$REMOVE" == true ]; then
                if [ "$DRY_RUN" == true ]; then
                    echo "[Dry-run] Would delete orphan image: $IMAGE_NAME"
                else
                    echo "Deleting orphan image: $IMAGE_NAME"
                    rm -f "$IMAGE"
                fi
            else
                echo "Skipped orphan image: $IMAGE_NAME"
            fi
        done

        for DTB in "${DTB_FILES[@]}"; do
            # Skip DTBs that were already processed (either deleted or marked as skipped)
            if [[ " ${PROCESSED_DTBS[@]} " =~ " ${DTB} " ]]; then
                continue
            fi

            DTB_NAME=$(basename "$DTB")
            LOCALVERSION=""

            # Extract LOCALVERSION from DTB name if available
            if [[ $DTB_NAME =~ tegra234-p3701-0000-p3737-0000(.*)\.dtb ]]; then
                LOCALVERSION="${BASH_REMATCH[1]}"
            else
                LOCALVERSION="default"
            fi

            REMOVE=true

            # If interactive, prompt the user
            if [ "$INTERACTIVE" == true ]; then
                echo -e "\n[LOCALVERSION: $LOCALVERSION]"
                echo "Orphan DTB: $DTB_NAME"
                read -p "Delete orphan DTB file? (default yes) [Y/n]: " CONFIRM
                case "$CONFIRM" in
                    [nN][oO]|[nN]) REMOVE=false ;;
                    *) REMOVE=true ;; # Default to yes
                esac
            fi

            # Proceed with deletion if confirmed
            if [ "$REMOVE" == true ]; then
                if [ "$DRY_RUN" == true ]; then
                    echo "[Dry-run] Would delete orphan DTB: $DTB_NAME"
                else
                    echo "Deleting orphan DTB: $DTB_NAME"
                    rm -f "$DTB"
                fi
            else
                echo "Skipped orphan DTB: $DTB_NAME"
            fi
        done
    fi
done

echo -e "\nKernel build cleanup complete."

