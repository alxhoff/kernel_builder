#!/bin/bash

# Script to list all built kernels and corresponding images inside the /kernels directory

KERNELS_DIR="../kernels"

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

        # Check for compiled kernel version modules in the modules directory
        echo "Kernel Name: $(basename "$KERNEL_NAME")"

        # List compiled kernel version modules
        BUILT_VERSIONS=()
        if [ -d "$MODULES_DIR" ]; then
            echo "Compiled Kernel Version Modules:"
            for VERSION in "$MODULES_DIR"/*; do
                if [ -d "$VERSION" ]; then
                    BUILT_VERSION=$(basename "$VERSION")
                    BUILT_VERSIONS+=("$BUILT_VERSION")

                    # Extract LOCALVERSION (everything after the first occurrence of a digit or period sequence)
                    LOCALVERSION=$(echo "$BUILT_VERSION" | sed -E 's/^[0-9.]+//')
                    echo "  - Version: $BUILT_VERSION (LOCALVERSION: $LOCALVERSION)"
                fi
            done
        else
            echo "  No compiled kernel version modules found."
        fi

        # List kernel images in boot directory
        if [ -d "$BOOT_DIR" ]; then
            echo "Kernel Images in Boot Directory:"
            for IMAGE in "$BOOT_DIR"/*; do
                if [ -f "$IMAGE" ]; then
                    IMAGE_NAME=$(basename "$IMAGE")
                    echo "  - $IMAGE_NAME"

                    # Extract LOCALVERSION from the image name if available
                    LOCALVERSION=$(echo "$IMAGE_NAME" | sed -n 's/^Image\.\(.*\)$/\1/p')

                    if [ -n "$LOCALVERSION" ]; then
                        echo "    -> LOCALVERSION: $LOCALVERSION"
                    else
                        echo "    -> LOCALVERSION: <none>"
                    fi

                    # Attempt to match the image to a kernel version if possible
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

