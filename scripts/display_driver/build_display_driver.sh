#!/bin/bash

set -e

# Default values
TOOLCHAIN_PATH=""
OUTPUT_DIR="$(pwd)/build"
KERNEL_SOURCES_DIR=""
CROSS_PREFIX="aarch64-buildroot-linux-gnu-"

# Constants
DRIVER_TAR_URL="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/sources/public_sources.tbz2"
WORK_DIR="$(pwd)/jetson_display_driver"
SOURCE_TARBALL="$WORK_DIR/public_sources.tbz2"
EXTRACTED_SOURCE_DIR="$WORK_DIR/Linux_for_Tegra/source/public"
DRIVER_TARBALL="$EXTRACTED_SOURCE_DIR/nvidia_kernel_display_driver_source.tbz2"
DRIVER_SOURCE_DIR="$EXTRACTED_SOURCE_DIR/nvdisplay"

# Function to show help
show_help() {
    echo "Usage: $0 --toolchain <path> --kernel-sources <path> [--output-dir <path>]"
    echo "Options:"
    echo "  --toolchain PATH       Path to the cross-compilation toolchain (required)"
    echo "  --kernel-sources PATH  Path to the kernel source directory (required)"
    echo "  --output-dir PATH      Optional: Path to the output directory (default: ./build)"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --toolchain)
            TOOLCHAIN_PATH=$(realpath "$2")
            shift 2
            ;;
        --kernel-sources)
            KERNEL_SOURCES_DIR=$(realpath "$2")
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR=$(realpath "$2")
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

# Validate required parameters
if [[ -z "$TOOLCHAIN_PATH" || -z "$KERNEL_SOURCES_DIR" ]]; then
    echo "Error: --toolchain and --kernel-sources are required."
    exit 1
fi

# Create work directory
mkdir -p "$WORK_DIR"

# Download and extract public sources if not already present
if [[ ! -d "$EXTRACTED_SOURCE_DIR" ]]; then
    echo "Downloading public sources..."
    wget -O "$SOURCE_TARBALL" "$DRIVER_TAR_URL"

    echo "Extracting public sources..."
    tar -xpf "$SOURCE_TARBALL" -C "$WORK_DIR"
fi

# Extract the driver sources if not already extracted
if [[ ! -d "$DRIVER_SOURCE_DIR" ]]; then
    echo "Extracting display driver sources..."
    tar -xpf "$DRIVER_TARBALL" -C "$EXTRACTED_SOURCE_DIR"
fi

# Add toolchain to PATH
export PATH="${TOOLCHAIN_PATH}/bin:$PATH"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Build the display driver
echo "Building NVIDIA Jetson display driver..."
make -C "$DRIVER_SOURCE_DIR" modules -j "$(nproc)" TARGET_ARCH=aarch64 ARCH=arm64 \
    CC="${CROSS_PREFIX}gcc" LD="${CROSS_PREFIX}ld" AR="${CROSS_PREFIX}ar" \
    CXX="${CROSS_PREFIX}g++" OBJCOPY="${CROSS_PREFIX}objcopy" \
    SYSOUT="$OUTPUT_DIR" SYSSRC="$KERNEL_SOURCES_DIR"

echo "Build complete. Output is in: $OUTPUT_DIR"

