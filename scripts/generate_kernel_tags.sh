#!/bin/bash

# Generate ctags for kernel source and overlays
# Usage: ./generate_kernel_tags.sh [options]
# Example: ./generate_kernel_tags.sh -k jetson

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNELS_DIR="$REPO_ROOT/kernels"
KERNEL_VERSION=""
KERNEL_DIR=""
KERNEL_SOURCE=""
OVERLAYS=()
TAGS_FILE=""

# Show help function
show_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -k, --kernel-version <version>  Specify the kernel version (required)"
    echo "  -h, --help                      Show this help message"
    echo
    echo "Examples:"
    echo "  $0 -k jetson"
    echo "  $0 -k vanilla_jetson"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -k|--kernel-version)
            KERNEL_VERSION="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Validate kernel version
if [[ -z "$KERNEL_VERSION" ]]; then
    echo "Error: Kernel version is required."
    echo
    show_help
fi

KERNEL_DIR="$KERNELS_DIR/$KERNEL_VERSION/kernel"

# Validate kernel directory
if [[ ! -d "$KERNEL_DIR" ]]; then
    echo "Error: Kernel directory not found at '$KERNEL_DIR'."
    exit 1
fi

# Validate kernel source
KERNEL_SOURCE="$KERNEL_DIR/kernel"
if [[ ! -d "$KERNEL_SOURCE" ]]; then
    echo "Error: Kernel source directory not found at '$KERNEL_SOURCE'."
    exit 1
fi

# Collect overlay directories from kernel/
for dir in "$KERNEL_DIR"/*; do
    if [[ -d "$dir" && "$dir" != "$KERNEL_SOURCE" && "$dir" != *kernel-5.10* ]]; then
        OVERLAYS+=("$dir")
    fi
done

# Determine the output tags file location
TAGS_FILE="$KERNEL_DIR/tags"
echo "Tags file will be placed at: $TAGS_FILE"

# Start generating tags
echo "Generating tags for kernel source: $KERNEL_SOURCE"
if [[ ${#OVERLAYS[@]} -gt 0 ]]; then
    echo "Including overlays:"
    for overlay in "${OVERLAYS[@]}"; do
        echo "  - $overlay"
    done
else
    echo "No overlays found."
fi

# Build the ctags command with references enabled
CTAGS_CMD="ctags --extras=+r --fields=+l --languages=c,c++ --kinds-c=+p -f $TAGS_FILE -R $KERNEL_SOURCE"
for overlay in "${OVERLAYS[@]}"; do
    CTAGS_CMD+=" $overlay"
done

# Execute the ctags command
echo "Running: $CTAGS_CMD"
eval "$CTAGS_CMD"

# Confirm completion
if [[ $? -eq 0 ]]; then
    echo "Tags successfully generated at: $TAGS_FILE"
else
    echo "Error: Failed to generate tags."
fi

