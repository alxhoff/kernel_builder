#!/bin/bash

# Script to list all built kernels and corresponding images inside the /kernels directory

KERNELS_DIR="kernels"

# Ensure the kernels directory exists
if [ ! -d "$KERNELS_DIR" ]; then
    echo "Error: Kernels directory '$KERNELS_DIR' does not exist."
    exit 1
fi

# Iterate through all kernel names in the kernels directory
for KERNEL_NAME in "$KERNELS_DIR"/*; do
    if [ -d "$KERNEL_NAME" ]; then
        MODULES_DIR="$KERNEL_NAME/modules/lib/modules"
        BOOT_DIR="$KERNEL_NAME/modules/boot"

        # Check for built kernel versions in the modules directory
        echo "Kernel Name: $(basename "$KERNEL_NAME")"

        # List built kernel versions
        BUILT_VERSIONS=()
        if [ -d "$MODULES_DIR" ]; then
            echo "Built Kernel Versions:"
            for VERSION in "$MODULES_DIR"/*; do
                if [ -d "$VERSION" ]; then
                    BUILT_VERSION=$(basename "$VERSION")
                    BUILT_VERSIONS+=("$BUILT_VERSION")
                    echo "  - $BUILT_VERSION"
                fi
            done
        else
            echo "  No built kernel versions found."
        fi

        # List kernel images in boot directory
        if [ -d "$BOOT_DIR" ]; then
            echo "Kernel Images in Boot Directory:"
            for IMAGE in "$BOOT_DIR"/*; do
                if [ -f "$IMAGE" ]; then
                    IMAGE_NAME=$(basename "$IMAGE")
                    echo "  - $IMAGE_NAME"

                    # Attempt to match the image to a kernel version if possible
                    # Extract the LOCALVERSION from the image name (assuming format Image.LOCALVERSION)
                    LOCALVERSION=$(echo "$IMAGE_NAME" | sed -n 's/^Image\.\(.*\)$/\1/p')

                    # Check if there's a matching kernel version using the LOCALVERSION
                    MATCHED_VERSION=""
                    for BUILT_VERSION in "${BUILT_VERSIONS[@]}"; do
                        if [[ "$BUILT_VERSION" == *"$LOCALVERSION" ]]; then
                            MATCHED_VERSION="$BUILT_VERSION"
                            break
                        fi
                    done

                    if [ -n "$MATCHED_VERSION" ]; then
                        echo "    -> Matches Kernel Version: $MATCHED_VERSION"
                    else
                        echo "    -> No matching kernel version found in modules directory"
                    fi
                fi
            done
        else
            echo "  No kernel images found in boot directory."
        fi
        echo ""
    fi
done

