#!/bin/bash

# Script to list all built kernels inside the /kernels directory

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

        # Check if modules directory exists
        if [ -d "$MODULES_DIR" ]; then
            echo "Kernel Name: $(basename "$KERNEL_NAME")"
            echo "Built Kernel Versions:"
            for VERSION in "$MODULES_DIR"/*; do
                if [ -d "$VERSION" ]; then
                    echo "  - $(basename "$VERSION")"
                fi
            done
            echo ""
        else
            echo "Kernel Name: $(basename "$KERNEL_NAME")"
            echo "  No built kernel versions found."
            echo ""
        fi
    fi
done

