#!/bin/bash

# Default kernel source path
DEFAULT_KERNEL_SRC="../kernels/sw_base_panic_logging/kernel/kernel"
DEFAULT_CROSS_COMPILE="../toolchains/aarch64-buildroot-linux-gnu/bin/aarch64-buildroot-linux-gnu-"
MODULE_SOURCE="panic_logger.c"
BUILD_DIR="build"

resolve_absolute_path() {
    local path="$1"
    echo "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
}

function show_help {
    echo "Usage: $0 [OPTIONS] [KERNEL_SOURCE] [CROSS_COMPILE]"
    echo ""
    echo "Build the panic_logger kernel module out-of-tree for ARCH=arm64."
    echo ""
    echo "Options:"
    echo "  --menuconfig    Run 'make menuconfig' after generating the default configuration."
    echo "  --help          Show this help message and exit."
    echo ""
    echo "Arguments:"
    echo "  KERNEL_SOURCE   Path to the kernel source tree. Defaults to:"
    echo "                  '$DEFAULT_KERNEL_SRC'"
    echo ""
    echo "  CROSS_COMPILE   Path to the cross-compilation toolchain prefix."
    echo "                  Defaults to:"
    echo "                  '$DEFAULT_CROSS_COMPILE'"
    echo ""
    echo "Example:"
    echo "  $0 --menuconfig /path/to/kernel/source /path/to/toolchain-prefix-"
    echo "  $0             # Uses default kernel source path and toolchain."
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

# Accept kernel source path and toolchain as arguments or use defaults
KERNEL_SRC="${1:-$DEFAULT_KERNEL_SRC}"
CROSS_COMPILE="${2:-$DEFAULT_CROSS_COMPILE}"
KERNEL_SRC=$(resolve_absolute_path "$KERNEL_SRC")
CROSS_COMPILE=$(resolve_absolute_path "$CROSS_COMPILE")
MODULE_SOURCE=$(resolve_absolute_path "$MODULE_SOURCE")
BUILD_DIR=$(resolve_absolute_path "$BUILD_DIR")

if [ ! -d "$KERNEL_SRC" ]; then
    echo "Error: Kernel source directory '$KERNEL_SRC' does not exist."
    exit 1
fi
if [ ! -f "$MODULE_SOURCE" ]; then
    echo "Error: Module source file '$MODULE_SOURCE' not found."
    exit 1
fi

echo "Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

handle_unclean_tree() {
    echo "Checking for an unclean source tree..."
    make -C "$KERNEL_SRC" ARCH=arm64 O="$BUILD_DIR" CROSS_COMPILE="$CROSS_COMPILE" tegra_defconfig >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Source tree is unclean. Running 'make mrproper'..."
        make -C "$KERNEL_SRC" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" mrproper
        if [ $? -ne 0 ]; then
            echo "Error: Failed to clean the kernel source tree."
            exit 1
        fi
        echo "Source tree cleaned successfully."
    else
        echo "Source tree is clean."
    fi
}

handle_unclean_tree

echo "Configuring kernel with tegra_defconfig..."
make -C "$KERNEL_SRC" ARCH=arm64 O="$BUILD_DIR" CROSS_COMPILE="$CROSS_COMPILE" tegra_defconfig
if [ $? -ne 0 ]; then
    echo "Error: Failed to configure kernel."
    exit 1
fi

if [ "$RUN_MENUCONFIG" = true ]; then
    echo "Running menuconfig..."
    make -C "$KERNEL_SRC" ARCH=arm64 O="$BUILD_DIR" CROSS_COMPILE="$CROSS_COMPILE" menuconfig
    if [ $? -ne 0 ]; then
        echo "Error: Failed to run menuconfig."
        exit 1
    fi
fi

echo "Preparing kernel for module building (modules_prepare)..."
make -C "$KERNEL_SRC" ARCH=arm64 O="$BUILD_DIR" CROSS_COMPILE="$CROSS_COMPILE" modules_prepare
if [ $? -ne 0 ]; then
    echo "Error: Failed to prepare kernel for module building."
    exit 1
fi

MODULE_DIR="$(dirname "$MODULE_SOURCE")"
TEMP_MAKEFILE="$MODULE_DIR/Makefile"
if [ ! -f "$TEMP_MAKEFILE" ]; then
    echo "Creating temporary Makefile for module build..."
    echo "obj-m := $(basename "$MODULE_SOURCE" .c).o" > "$TEMP_MAKEFILE"
    TEMP_MAKEFILE_CREATED=true
else
    TEMP_MAKEFILE_CREATED=false
fi

echo "Building module '$MODULE_SOURCE'..."
make -C "$KERNEL_SRC" ARCH=arm64 O="$BUILD_DIR" CROSS_COMPILE="$CROSS_COMPILE" M="$MODULE_DIR" modules
if [ $? -ne 0 ]; then
    echo "Error: Failed to build module."
    if [ "$TEMP_MAKEFILE_CREATED" = true ]; then
        echo "Removing temporary Makefile..."
        rm -f "$TEMP_MAKEFILE"
    fi
    exit 1
fi

if [ "$TEMP_MAKEFILE_CREATED" = true ]; then
    echo "Removing temporary Makefile..."
    rm -f "$TEMP_MAKEFILE"
fi

echo "Module built successfully. Output:"
echo "  Module: $MODULE_DIR/$(basename "$MODULE_SOURCE" .c).ko"

