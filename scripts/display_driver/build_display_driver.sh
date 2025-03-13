#!/bin/bash

set -ex

CROSS_PREFIX="aarch64-buildroot-linux-gnu-"
TOOLCHAIN_PATH=""
KERNEL_SOURCES_DIR=""

WORK_DIR="$(pwd)/jetson_display_driver"
KERNEL_OUT_DIR="$(pwd)/kernel_out"

BSP_SOURCES_TAR_URL="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/sources/public_sources.tbz2"
BSP_SOURCES_TAR="$WORK_DIR/public_sources.tbz2"
NVDISPLAY_TAR_DIR="$WORK_DIR/Linux_for_Tegra/source/public"
NVDISPLAY_TAR="$NVDISPLAY_TAR_DIR/nvidia_kernel_display_driver_source.tbz2"
NVDISPLAY_SOURCE_DIR="$NVDISPLAY_TAR_DIR/nvdisplay"

KERNEL_TARGET_DIR="$WORK_DIR/kernel_src/kernel/kernel-5.10"

show_help() {
    echo "Usage: $0 --toolchain <path> --kernel-sources <path> [--output-dir <path>]"
    echo "Options:"
    echo "  --toolchain PATH       Path to the cross-compilation toolchain, ie. path $TO_HERE/bin/aarch64... (required)"
    echo "  --kernel-sources PATH  Path to the kernel source directory (required)"
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

if [[ -d "$KERNEL_TARGET_DIR" && -n "$(ls -A "$KERNEL_TARGET_DIR")" ]]; then
    echo "Kernel source already exists at '$KERNEL_TARGET_DIR' and is not empty. Skipping copy."
else
	cp -r $KERNEL_SOURCES_DIR/../.. "$WORK_DIR/kernel_src"
    SOURCE_DIR=$(find "$WORK_DIR/kernel_src/kernel/" -mindepth 1 -maxdepth 1 -type d -name "kernel*" ! -name "kernel-5.10" | head -n 1)
    if [ -n "$SOURCE_DIR" ]; then
        mv "$SOURCE_DIR" "$KERNEL_TARGET_DIR"
        echo "Folder renamed to 'kernel-5.10'."
    else
        echo "No matching folder found to rename."
    fi
fi

if [[ ! -d "$NVDISPLAY_TAR_DIR" ]]; then
    echo "Downloading and extracting public sources..."
    wget -O "$BSP_SOURCES_TAR" "$BSP_SOURCES_TAR_URL"
    tar -xpf "$BSP_SOURCES_TAR" -C "$WORK_DIR"
fi

if [[ ! -d "$NVDISPLAY_SOURCE_DIR" ]]; then
    echo "Extracting display driver sources..."
    tar -xpf "$NVDISPLAY_TAR" -C "$NVDISPLAY_TAR_DIR"
fi

echo "Preparing kernel sources..running mrproper inside kernel source and cleaning kernel output dir"
make -C "$KERNEL_TARGET_DIR" -j "$(nproc)" ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE_PATH} LOCALVERSION="-cartken5.1.3" mrproper

if [[ -d "$KERNEL_OUT_DIR" ]]; then
    rm -rf "$KERNEL_OUT_DIR"
fi
mkdir -p "$KERNEL_OUT_DIR"

echo "Cleaned with mrproper, applying defconfig"
make -C "$KERNEL_TARGET_DIR" O=$KERNEL_OUT_DIR -j "$(nproc)" ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE_PATH} LOCALVERSION="-cartken5.1.3" defconfig

echo "Tegra defconfig applied, building kernel"
make -C "$KERNEL_TARGET_DIR" O=$KERNEL_OUT_DIR -j "$(nproc)" ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE_PATH} LOCALVERSION="-cartken5.1.3"

echo "Kernel built. Building NVIDIA Jetson display driver..."

IGNORE_MISSING_MODULE_SYMVERS=1 make VERBOSE=1 -C "$NVDISPLAY_SOURCE_DIR" modules \
	TARGET_ARCH=aarch64 ARCH=arm64 \
	LOCALVERSION="-cartken5.1.3" \
    CC="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}gcc" \
    LD="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}ld.bfd" \
    AR="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}ar" \
    CXX="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}g++" \
    OBJCOPY="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}objcopy" \
    SYSOUT="$KERNEL_OUT_DIR" SYSSRC="$KERNEL_TARGET_DIR"

echo "Build complete. Output is in: $KERNEL_OUT_DIR"

