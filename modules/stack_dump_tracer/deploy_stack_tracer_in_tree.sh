#!/bin/bash

# Function to display usage
function usage() {
    echo "Usage: $0 [--interactive] | <kernel_name>"
    echo "Options:"
    echo "  --interactive       Search for kernels and allow user selection"
    exit 1
}

# Function for interactive kernel selection
function interactive_mode() {
    local script_dir="$(dirname "$(realpath "$0")")"
    local kernels_dir="$script_dir/../../kernels"

    # Ensure the kernels directory exists
    if [ ! -d "$kernels_dir" ]; then
        echo "Error: Kernels directory not found: $kernels_dir"
        exit 1
    fi

    # Search for kernel directories
    local kernel_names=()
    for dir in "$kernels_dir"/*; do
        if [ -d "$dir" ]; then
            kernel_names+=("$(basename "$dir")")
        fi
    done

    if [ ${#kernel_names[@]} -eq 0 ]; then
        echo "No kernel directories found in $kernels_dir"
        exit 1
    fi

    # List the kernels for user selection
    echo "Available kernels:"
    for i in "${!kernel_names[@]}"; do
        echo "  [$i] ${kernel_names[i]}"
    done

    # Prompt the user to select a kernel
    while true; do
        read -p "Select a kernel by index (0-$((${#kernel_names[@]} - 1))): " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 0 ] && [ "$selection" -lt ${#kernel_names[@]} ]; then
            KERNEL_NAME="${kernel_names[$selection]}"
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done
}

# Main script logic
if [ "$1" == "--interactive" ]; then
    interactive_mode
else
    KERNEL_NAME="$1"
    if [ -z "$KERNEL_NAME" ]; then
        usage
    fi
fi

# Validate kernel name
if [ -z "$KERNEL_NAME" ]; then
    echo "Error: No kernel name provided."
    exit 1
fi

# Determine paths relative to the script location
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
DRIVER_DIR="$SCRIPT_DIR/../../kernels/${KERNEL_NAME}/kernel/nvidia/drivers/misc/stack_tracer"
HEADER_DIR="$SCRIPT_DIR/../../kernels/${KERNEL_NAME}/kernel/nvidia/include/trace/events"

# Ensure the target directories exist
echo "Creating target directories: $DRIVER_DIR and $HEADER_DIR"
mkdir -p "$DRIVER_DIR" "$HEADER_DIR"

# Files to deploy
DRIVER_FILES=("stack_tracer.c" "Kconfig" "Makefile")
HEADER_FILE="stack_tracer.h"

# Copy driver files to the target directory
for file in "${DRIVER_FILES[@]}"; do
    SOURCE_PATH="$SCRIPT_DIR/$file"
    TARGET_PATH="$DRIVER_DIR/$file"
    if [[ -f "$SOURCE_PATH" ]]; then
        echo "Copying driver file: $SOURCE_PATH -> $TARGET_PATH"
        cp -f "$SOURCE_PATH" "$TARGET_PATH"
    else
        echo "Warning: Driver file $SOURCE_PATH does not exist and will not be copied."
    fi
done

# Copy header file to the target directory
SOURCE_PATH="$SCRIPT_DIR/$HEADER_FILE"
TARGET_PATH="$HEADER_DIR/$HEADER_FILE"
if [[ -f "$SOURCE_PATH" ]]; then
    echo "Copying header file: $SOURCE_PATH -> $TARGET_PATH"
    cp -f "$SOURCE_PATH" "$TARGET_PATH"
else
    echo "Warning: Header file $SOURCE_PATH does not exist and will not be copied."
fi

# Check and update the parent Kconfig
PARENT_KCONFIG="$SCRIPT_DIR/../../kernels/${KERNEL_NAME}/kernel/nvidia/drivers/misc/Kconfig"
KCONFIG_ENTRY='source "drivers/misc/stack_tracer/Kconfig"'
if ! grep -Fxq "$KCONFIG_ENTRY" "$PARENT_KCONFIG"; then
    echo "Adding Kconfig entry to $PARENT_KCONFIG"
    if grep -q "endmenu" "$PARENT_KCONFIG"; then
        sed -i "/endmenu/i $KCONFIG_ENTRY" "$PARENT_KCONFIG"
    else
        echo "$KCONFIG_ENTRY" >> "$PARENT_KCONFIG"
    fi
else
    echo "Kconfig entry already exists in $PARENT_KCONFIG"
fi

# Check and update the parent Makefile
PARENT_MAKEFILE="$SCRIPT_DIR/../../kernels/${KERNEL_NAME}/kernel/nvidia/drivers/misc/Makefile"
MAKEFILE_ENTRY='obj-$(CONFIG_STACK_TRACER) += stack_tracer/'
if ! grep -Fxq "$MAKEFILE_ENTRY" "$PARENT_MAKEFILE"; then
    echo "Adding Makefile entry to $PARENT_MAKEFILE"
    echo "$MAKEFILE_ENTRY" >> "$PARENT_MAKEFILE"
else
    echo "Makefile entry already exists in $PARENT_MAKEFILE"
fi

# Final message
echo "Stack tracer files deployed successfully to kernel: $KERNEL_NAME."
echo "Ensure the kernel is configured and rebuilt to include the stack tracer module."

