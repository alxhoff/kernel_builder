#!/bin/bash

# Variables
KERNEL_NAME=$1
BASE_DIR=$(dirname "$(realpath "$0")")
KERNEL_DIR="$BASE_DIR/../../kernels/$KERNEL_NAME/kernel/kernel"
TOOLCHAIN_DIR="$BASE_DIR/../../toolchains/aarch64-buildroot-linux-gnu"
TARGET_MODULES_FILE="$BASE_DIR/../../target_modules.txt"
OUTPUT_DIR="$BASE_DIR/check_results"
CROSS_COMPILE="${TOOLCHAIN_DIR}/bin/aarch64-buildroot-linux-gnu-"
ARCH="arm64"

# Ensure kernel name is provided
if [ -z "$KERNEL_NAME" ]; then
    echo "Usage: $0 <kernel_name>"
    exit 1
fi

# Prepare output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Ensure target modules file exists
if [ ! -f "$TARGET_MODULES_FILE" ]; then
    echo "Target modules file not found: $TARGET_MODULES_FILE"
    exit 1
fi

# Read target modules
MODULES=$(cat "$TARGET_MODULES_FILE")

# Build kernel headers
echo "Building kernel headers..."
make -C "$KERNEL_DIR" ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE prepare > "$OUTPUT_DIR/kernel_prepare.log" 2>&1
if [ $? -ne 0 ]; then
    echo "Kernel headers preparation failed. Check $OUTPUT_DIR/kernel_prepare.log"
    exit 1
fi

# Iterate over modules and run checks
for MODULE in $MODULES; do
    MODULE_PATH="$KERNEL_DIR/${MODULE%.ko}.c"
    MODULE_NAME=$(basename "$MODULE")

    if [ ! -f "$MODULE_PATH" ]; then
        echo "Module source not found: $MODULE_PATH"
        echo "Skipping $MODULE_NAME..."
        continue
    fi

    # Sparse command
    echo "Running Sparse for $MODULE_NAME..."
    sparse -D__KERNEL__ -D__LINUX_ARM_ARCH__=8 -D__ARM64__ \
           -DCONFIG_TREE_RCU -DCONFIG_HZ=250 -DCONFIG_PGTABLE_LEVELS=4 \
           -DCONFIG_ARM_ARCH_TIMER_OOL_WORKAROUND=1 \
           -DCONFIG_ARCH_ENABLE_SPLIT_PMD_PTLOCK=0 \
           -DCONFIG_ZSMALLOC=0 \
           -DCONFIG_SHADOW_CALL_STACK=0 \
           -I"$KERNEL_DIR" \
           -I"$KERNEL_DIR/include" \
           -I"$KERNEL_DIR/include/generated" \
           -I"$KERNEL_DIR/arch/arm64/include" \
           -I"$KERNEL_DIR/arch/arm64/include/generated" \
           -I"$KERNEL_DIR/arch/arm64/include/generated/uapi" \
           -I"$KERNEL_DIR/include/uapi" \
           -I"$KERNEL_DIR/arch/arm64/include/uapi" \
           -I"$KERNEL_DIR/nvidia/include" \
           -I"$TOOLCHAIN_DIR/lib/gcc/aarch64-buildroot-linux-gnu/9.3.0/include" \
           -I"$TOOLCHAIN_DIR/lib/gcc/aarch64-buildroot-linux-gnu/9.3.0/include-fixed" \
           -I"$TOOLCHAIN_DIR/aarch64-buildroot-linux-gnu/include" \
           "$MODULE_PATH" > "$OUTPUT_DIR/$MODULE_NAME.sparse.log" 2>&1

    if [ $? -ne 0 ]; then
        echo "Sparse failed for $MODULE_NAME. Check $OUTPUT_DIR/$MODULE_NAME.sparse.log"
        continue
    fi

    # Smatch command
    echo "Running Smatch for $MODULE_NAME..."
    smatch -p=kernel -I"$KERNEL_DIR" -I"$KERNEL_DIR/include" -I"$KERNEL_DIR/nvidia/include" \
           "$MODULE_PATH" > "$OUTPUT_DIR/$MODULE_NAME.smatch.log" 2>&1

    if [ $? -ne 0 ]; then
        echo "Smatch failed for $MODULE_NAME. Check $OUTPUT_DIR/$MODULE_NAME.smatch.log"
    fi
done

echo "All checks completed. Results are in $OUTPUT_DIR."

