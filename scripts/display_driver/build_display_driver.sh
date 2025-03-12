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
KERNEL_SOURCES_DIR="$WORK_DIR/kernel_src/kernel/kernel-5.10"
SOURCE_TARBALL="$WORK_DIR/public_sources.tbz2"
EXTRACTED_SOURCE_DIR="$WORK_DIR/Linux_for_Tegra/source/public"
DRIVER_TARBALL="$EXTRACTED_SOURCE_DIR/nvidia_kernel_display_driver_source.tbz2"
DRIVER_SOURCE_DIR="$EXTRACTED_SOURCE_DIR/nvdisplay"

show_help() {
    echo "Usage: $0 --toolchain <path> --kernel-sources <path> [--output-dir <path>]"
    echo "Options:"
    echo "  --toolchain PATH       Path to the cross-compilation toolchain, ie. path $TO_HERE/bin/aarch64... (required)"
    echo "  --kernel-sources PATH  Path to the kernel source directory (required)"
    echo "  --output-dir PATH      Optional: Path to the output directory (default: ./build)"
    exit 0
}

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

CROSS_COMPILE_PATH="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}"

if [[ -z "$TOOLCHAIN_PATH" || -z "$KERNEL_SOURCES_DIR" ]]; then
    echo "Error: --toolchain and --kernel-sources are required."
    exit 1
fi

mkdir -p "$WORK_DIR"

if [ -d "$KERNEL_SOURCES_DIR" ]; then
    echo "The folder is already named 'kernel-5.10'. Skipping rename."
else
	cp -r $KERNEL_SOURCES_DIR/../.. "$WORK_DIR/kernel_src"
    SOURCE_DIR=$(find "$WORK_DIR/kernel_src/kernel/" -mindepth 1 -maxdepth 1 -type d -name "kernel*" ! -name "kernel-5.10" | head -n 1)
    if [ -n "$SOURCE_DIR" ]; then
        mv "$SOURCE_DIR" "$KERNEL_SOURCES_DIR"
        echo "Folder renamed to 'kernel-5.10'."
    else
        echo "No matching folder found to rename."
    fi
fi

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

echo "Preparing kernel sources..running mrproper"
make -C "$KERNEL_SOURCES_DIR" O=$OUTPUT_DIR -j "$(nproc)" ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE_PATH} LOCALVERSION="-cartken5.1.3" mrproper
if [[ -d "$OUTPUT_DIR" ]]; then
    echo "Removing existing output directory: $OUTPUT_DIR"
    rm -rf "$OUTPUT_DIR"
fi
mkdir -p "$OUTPUT_DIR"

echo "Cleaned with mrproper, applying defconfig"
make -C "$KERNEL_SOURCES_DIR" O=$OUTPUT_DIR -j "$(nproc)" ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE_PATH} LOCALVERSION="-cartken5.1.3" defconfig

echo "Tegra defconfig applied, building kernel"
make -C "$KERNEL_SOURCES_DIR" O=$OUTPUT_DIR -j "$(nproc)" ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE_PATH} LOCALVERSION="-cartken5.1.3"

echo "Kernel built. Building NVIDIA Jetson display driver..."

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

