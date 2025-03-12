#!/bin/bash

set -ex

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
    echo "  --toolchain PATH       Path to the cross-compilation toolchain, ie. path $TO_HERE/bin/aarch64... (required)"
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

mkdir -p "$WORK_DIR"

if [[ ! -d "$EXTRACTED_SOURCE_DIR" ]]; then
    echo "Downloading public sources..."
    wget -O "$SOURCE_TARBALL" "$DRIVER_TAR_URL"

    echo "Extracting public sources..."
    tar -xpf "$SOURCE_TARBALL" -C "$WORK_DIR"
fi

if [[ ! -d "$DRIVER_SOURCE_DIR" ]]; then
    echo "Extracting display driver sources..."
    tar -xpf "$DRIVER_TARBALL" -C "$EXTRACTED_SOURCE_DIR"
fi

# Add toolchain to PATH
export PATH="${TOOLCHAIN_PATH}/bin:$PATH"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

echo "Preparing kernel sources..."
make -C "$KERNEL_SOURCES_DIR" -j "$(nproc)" ARCH=arm64 CROSS_COMPILE=${CROSS_PREFIX} LOCALVERSION="-cartken5.1.3" mrproper
echo "Cleaned with mrproper"
make -C "$KERNEL_SOURCES_DIR" -j "$(nproc)" ARCH=arm64 CROSS_COMPILE=${CROSS_PREFIX} LOCALVERSION="-cartken5.1.3" defconfig
echo "Tegra defconfig applied"
make -C "$KERNEL_SOURCES_DIR" -j "$(nproc)" ARCH=arm64 CROSS_COMPILE=${CROSS_PREFIX} LOCALVERSION="-cartken5.1.3"
echo "Kernel built"
make -C "$KERNEL_SOURCES_DIR" -j "$(nproc)" ARCH=arm64 CROSS_COMPILE=${CROSS_PREFIX} LOCALVERSION="-cartken5.1.3" modules_prepare
echo "Modules prepared"

export ARCH=arm64
echo "ARCH: $ARCH"
export TARGET_ARCH=aarch64
echo "TARGET_ARCH: ${TARGET_ARCH}"
export CROSS_COMPILE="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}"
echo "CROSS_COMPILE: $CROSS_COMPILE"
export CROSS_COMPILE_AARCH64_PATH=${TOOLCHAIN_PATH}
export CROSS_COMPILE_AARCH64=${CROSS_COMPILE}
export LOCALVERSION="-cartken5.1.3"

echo "Building NVIDIA Jetson display driver..."

cd $DRIVER_SOURCE_DIR

echo "Running following command to build display driver"
echo "IGNORE_MISSING_MODULE_SYMVERS=1 make VERBOSE=1 -C "$DRIVER_SOURCE_DIR" modules \
	TARGET_ARCH=aarch64 ARCH=arm64 \
	LOCALVERSION="-cartken5.1.3" \
    CC="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}gcc" \
    LD="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}ld.bfd" \
    AR="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}ar" \
    CXX="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}g++" \
    OBJCOPY="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}objcopy" \
    SYSOUT="$OUTPUT_DIR" SYSSRC="$KERNEL_SOURCES_DIR""

IGNORE_MISSING_MODULE_SYMVERS=1 make VERBOSE=1 -C "$DRIVER_SOURCE_DIR" modules \
	TARGET_ARCH=aarch64 ARCH=arm64 \
	LOCALVERSION="-cartken5.1.3" \
    CC="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}gcc" \
    LD="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}ld.bfd" \
    AR="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}ar" \
    CXX="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}g++" \
    OBJCOPY="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}objcopy" \
    SYSOUT="$OUTPUT_DIR" SYSSRC="$KERNEL_SOURCES_DIR"

echo "Build complete. Output is in: $OUTPUT_DIR"

