#!/bin/bash

# Combined and Simplified Build Script for NVIDIA Kernel Sources

# Constants
SCRIPT_DIR="$(dirname $(readlink -f "$0"))"
NPROC=$(nproc)
MAKE_BIN="make"
BUILD_DIR="${SCRIPT_DIR}/build_nv_sources"
KERNEL_VERSION="5.10"
CROSS_COMPILE_AARCH64=""
CROSS_COMPILE_AARCH64_PATH=""
CROSS_COMPILE_AARCH64_PATH=""

# Usage Information
function usage {
    echo "Usage: $0 [OPTIONS]"
    echo "  -p <cross_compile_path> Set the cross compiler prefix path (e.g., /usr/bin/aarch64-linux-gnu-)"
echo "Options:"
    echo "  -h              Display this help message"
    echo "  -o <outdir>     Set the output directory for the kernel build"
    echo "  -c <cross_comp> Set the cross compiler path"
}

# Parse Command-Line Arguments
function parse_args {
    while [ $# -gt 0 ]; do
        case $1 in
            -h)
                usage
                exit 0
                ;;
            -o)
                KERNEL_OUT_DIR="$2"
                shift 2
                ;;
            -c)
                CROSS_COMPILE_AARCH64="$2"
                shift 2
                ;;
            -p)
                CROSS_COMPILE_AARCH64_PATH="$2"
                shift 2
                shift 2
                ;;
            *)
                echo "Error: Invalid option $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check Cross Compilation Environment
function check_env {
    if [ -n "$CROSS_COMPILE_AARCH64_PATH" ]; then
        CROSS_COMPILE_AARCH64="$CROSS_COMPILE_AARCH64_PATH"
    fi
        if [ ! -f "${CROSS_COMPILE_AARCH64}gcc" ]; then
            echo "Error: Cross compiler not found at ${CROSS_COMPILE_AARCH64}gcc"
            exit 1
        fi
    fi
}

# Build Kernel Sources for ARM64 Architecture
function build_kernel {
    echo "Building kernel version ${KERNEL_VERSION}..."

    local source_dir="${SCRIPT_DIR}/kernel/kernel-${KERNEL_VERSION}/"
    local config_file="tegra_defconfig"
    local output_dir="${KERNEL_OUT_DIR:-$source_dir}"

    # Run make commands to configure and build the kernel
    $MAKE_BIN -C "$source_dir" ARCH=arm64 \
        LOCALVERSION="-tegra" \
        CROSS_COMPILE="$CROSS_COMPILE_AARCH64" \
        O="$output_dir" "$config_file" \
        KCFLAGS="-Wno-error=address -Wno-error=dangling-pointer"

    $MAKE_BIN -C "$source_dir" ARCH=arm64 \
        LOCALVERSION="-tegra" \
        CROSS_COMPILE="$CROSS_COMPILE_AARCH64" \
        O="$output_dir" -j"$NPROC" Image dtbs modules \
        KCFLAGS="-Wno-error=address -Wno-error=dangling-pointer"

    # Check if the kernel image was successfully created
    local image="${output_dir}/arch/arm64/boot/Image"
    if [ ! -f "$image" ]; then
        echo "Error: Kernel image not found at $image"
        exit 1
    fi

    echo "Kernel built successfully."
}

# Main Execution Flow
parse_args "$@"
check_env
build_kernel

