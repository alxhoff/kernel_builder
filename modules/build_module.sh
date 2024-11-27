#!/bin/bash

# Resolve the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default kernel source path (relative to script directory)
DEFAULT_KERNEL_SRC="$SCRIPT_DIR/../kernels/sw_base_panic_logging/kernel/kernel"
DEFAULT_CROSS_COMPILE="$SCRIPT_DIR/../toolchains/aarch64-buildroot-linux-gnu/bin/aarch64-buildroot-linux-gnu-"

resolve_absolute_path() {
    local path="$1"
    echo "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
}

function show_help {
    echo "Usage: $0 [OPTIONS] [MODULE_SOURCE] [KERNEL_SOURCE] [CROSS_COMPILE]"
    echo ""
    echo "Build a kernel module out-of-tree for ARCH=arm64."
    echo ""
    echo "Options:"
    echo "  --menuconfig    Run 'make menuconfig' after generating the default configuration."
    echo "  --help          Show this help message and exit."
    echo ""
    echo "Arguments:"
    echo "  MODULE_SOURCE   Path to the module source file (e.g., panic_logger.c)."
    echo ""
    echo "  KERNEL_SOURCE   Path to the kernel source tree. Defaults to:"
    echo "                  '$DEFAULT_KERNEL_SRC'"
    echo ""
    echo "  CROSS_COMPILE   Path to the cross-compilation toolchain prefix."
    echo "                  Defaults to:"
    echo "                  '$DEFAULT_CROSS_COMPILE'"
    echo ""
    echo "Example:"
    echo "  $0 panic_logger.c /path/to/kernel/source /path/to/toolchain-prefix-"
}

# Parse options
RUN_MENUCONFIG=false
while [[ "$1" == --* ]]; do
    case "$1" in
        --menuconfig)
            RUN_MENUCONFIG=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Accept module source path, kernel source path, and toolchain as arguments or use defaults
MODULE_SOURCE="${1}"
KERNEL_SRC="${2:-$DEFAULT_KERNEL_SRC}"
CROSS_COMPILE="${3:-$DEFAULT_CROSS_COMPILE}"

if [ -z "$MODULE_SOURCE" ]; then
    echo "Error: MODULE_SOURCE is required."
    show_help
    exit 1
fi

MODULE_SOURCE=$(resolve_absolute_path "$MODULE_SOURCE")
KERNEL_SRC=$(resolve_absolute_path "$KERNEL_SRC")
CROSS_COMPILE=$(resolve_absolute_path "$CROSS_COMPILE")

if [ ! -f "$MODULE_SOURCE" ]; then
    echo "Error: Module source file '$MODULE_SOURCE' not found."
    exit 1
fi

MODULE_DIR=$(dirname "$MODULE_SOURCE")
MODULE_NAME=$(basename "$MODULE_SOURCE" .c)
BUILD_DIR="$MODULE_DIR/build"
BUILD_LOG="$MODULE_DIR/build.log"

echo "Cleaning build directory for module..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "Cleaning previous log file..."
rm -f "$BUILD_LOG"

handle_unclean_tree() {
    echo "Checking for an unclean source tree..."
    make -C "$KERNEL_SRC" ARCH=arm64 O="$BUILD_DIR" CROSS_COMPILE="$CROSS_COMPILE" tegra_defconfig >>"$BUILD_LOG" 2>&1
    if [ $? -ne 0 ]; then
        echo "Source tree is unclean. Running 'make mrproper'..."
        make -C "$KERNEL_SRC" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" mrproper >>"$BUILD_LOG" 2>&1
        if [ $? -ne 0 ]; then
            echo "Error: Failed to clean the kernel source tree. Check $BUILD_LOG for details."
            exit 1
        fi
        echo "Source tree cleaned successfully."
    else
        echo "Source tree is clean."
    fi
}

handle_unclean_tree

echo "Configuring kernel with tegra_defconfig..."
make -C "$KERNEL_SRC" ARCH=arm64 O="$BUILD_DIR" CROSS_COMPILE="$CROSS_COMPILE" tegra_defconfig >>"$BUILD_LOG" 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to configure kernel. Check $BUILD_LOG for details."
    exit 1
fi

if [ "$RUN_MENUCONFIG" = true ]; then
    echo "Running menuconfig..."
    make -C "$KERNEL_SRC" ARCH=arm64 O="$BUILD_DIR" CROSS_COMPILE="$CROSS_COMPILE" menuconfig >>"$BUILD_LOG" 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to run menuconfig. Check $BUILD_LOG for details."
        exit 1
    fi
fi

echo "Preparing kernel for module building (modules_prepare)..."
make -C "$KERNEL_SRC" ARCH=arm64 O="$BUILD_DIR" CROSS_COMPILE="$CROSS_COMPILE" modules_prepare >>"$BUILD_LOG" 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to prepare kernel for module building. Check $BUILD_LOG for details."
    exit 1
fi

TEMP_MAKEFILE="$MODULE_DIR/Makefile"
echo "Creating temporary Makefile for module build..."
echo "obj-m := $MODULE_NAME.o" > "$TEMP_MAKEFILE"

echo "Building module '$MODULE_SOURCE'..."
make -C "$KERNEL_SRC" ARCH=arm64 O="$BUILD_DIR" CROSS_COMPILE="$CROSS_COMPILE" M="$MODULE_DIR" modules
# make -C "$KERNEL_SRC" ARCH=arm64 O="$BUILD_DIR" CROSS_COMPILE="$CROSS_COMPILE" M="$MODULE_DIR" modules >>"$BUILD_LOG" 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to build module. Check $BUILD_LOG for details."
    rm -f "$TEMP_MAKEFILE"
    exit 1
fi

rm -f "$TEMP_MAKEFILE"

echo "Module built successfully. Output:"
echo "  Module: $MODULE_DIR/$MODULE_NAME.ko"
echo "Build log: $BUILD_LOG"

