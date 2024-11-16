#!/bin/bash

# Script to list all built kernels and corresponding images inside the /kernels directory
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
KERNELS_DIR="$SCRIPT_DIR/../../kernels"

# Ensure the kernels directory exists
if [ ! -d "$KERNELS_DIR" ]; then
    echo "Error: Kernels directory '$KERNELS_DIR' does not exist."
    exit 1
fi

# Iterate through all kernel names in the kernels directory
for KERNEL_PATH in "$KERNELS_DIR"/*; do
    if [ -d "$KERNEL_PATH" ]; then
        KERNEL_NAME=$(basename "$KERNEL_PATH")
        MODULES_DIR="$KERNEL_PATH/modules/lib/modules"
        BOOT_DIR="$KERNEL_PATH/modules/boot"

        echo "========================================================================="
        echo "Kernel Name: $KERNEL_NAME"
        echo "========================================================================="

        # Reset the map to store kernel versions and their components for each kernel
        declare -A KERNEL_COMPONENTS=()

        # Gather Modules for the current kernel
        if [ -d "$MODULES_DIR" ]; then
            for VERSION in "$MODULES_DIR"/*; do
                if [ -d "$VERSION" ]; then
                    BUILT_VERSION=$(basename "$VERSION")
                    LOCALVERSION="${BUILT_VERSION#5.10.120}"
                    KERNEL_COMPONENTS[$LOCALVERSION]="Modules: $BUILT_VERSION"
                fi
            done
        fi

        # Gather Kernel Images for the current kernel
        if [ -d "$BOOT_DIR" ]; then
            for IMAGE in "$BOOT_DIR"/Image*; do
                if [ -f "$IMAGE" ]; then
                    IMAGE_NAME=$(basename "$IMAGE")
                    # Extract kernel version using "strings" and "grep"
                    KERNEL_VERSION=$(strings "$IMAGE" | grep -oP "Linux version \K[0-9\.]+[^\s]*")
                    LOCALVERSION="${KERNEL_VERSION#5.10.120}"

                    [ -z "$LOCALVERSION" ] && LOCALVERSION="default"

                    if [ -n "${KERNEL_COMPONENTS[$LOCALVERSION]}" ]; then
                        KERNEL_COMPONENTS[$LOCALVERSION]+=", Image: $IMAGE_NAME"
                    else
                        KERNEL_COMPONENTS[$LOCALVERSION]="Image: $IMAGE_NAME"
                    fi
                fi
            done

            # Gather DTB files for the current kernel
            for DTB in "$BOOT_DIR"/tegra234-p3701-0000-p3737-0000*.dtb; do
                if [ -f "$DTB" ]; then
                    DTB_NAME=$(basename "$DTB")
                    LOCALVERSION=$(echo "$DTB_NAME" | sed -n 's/^tegra234-p3701-0000-p3737-0000\(.*\)\.dtb$/\1/p')
                    [ -z "$LOCALVERSION" ] && LOCALVERSION="default"

                    if [ -n "${KERNEL_COMPONENTS[$LOCALVERSION]}" ]; then
                        KERNEL_COMPONENTS[$LOCALVERSION]+=", DTB: $DTB_NAME"
                    else
                        KERNEL_COMPONENTS[$LOCALVERSION]="DTB: $DTB_NAME"
                    fi
                fi
            done
        fi

        # Display grouped output by kernel version for the current kernel
        if [ ${#KERNEL_COMPONENTS[@]} -eq 0 ]; then
            echo "No components found for kernel $KERNEL_NAME."
        else
            for VERSION in "${!KERNEL_COMPONENTS[@]}"; do
                echo -e "\nKernel Version: 5.10.120$VERSION"
                COMPONENTS=${KERNEL_COMPONENTS[$VERSION]}

                # Split the components and display each on a new line
                IFS=',' read -ra COMPONENT_ARRAY <<< "$COMPONENTS"
                for COMPONENT in "${COMPONENT_ARRAY[@]}"; do
                    echo "  $COMPONENT"
                done
            done
        fi

        echo ""

        # Unset the associative array to ensure a clean slate for the next kernel
        unset KERNEL_COMPONENTS
    fi
done

