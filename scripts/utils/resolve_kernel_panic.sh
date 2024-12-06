#!/bin/bash

# Default values
DEFAULT_TOOLCHAIN="aarch64-buildroot-linux-gnu"
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
TOOLCHAIN_DIR="$SCRIPT_DIR/../../toolchains"
KERNELS_DIR="$SCRIPT_DIR/../../kernels"

# Parse arguments
TOOLCHAIN="$DEFAULT_TOOLCHAIN"
KERNEL_NAME=""
ADDRESS_LINE=""

print_usage() {
    echo "Usage: $0 --kernel-name <kernel_name> [--toolchain <toolchain_name>] <address_line>"
    echo ""
    echo "Arguments:"
    echo "  --kernel-name    Name of the kernel to locate the vmlinux file (required)"
    echo "  --toolchain      Toolchain name to locate addr2line (default: $DEFAULT_TOOLCHAIN)"
    echo "  <address_line>   Kernel panic log line containing the function and offset"
    echo ""
    echo "Example:"
    echo "  $0 --kernel-name my_kernel --toolchain aarch64-buildroot-linux-gnu '[  111.458579]  vi_capture_ivc_send_control.isra.0+0x100/0x120'"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --toolchain)
            TOOLCHAIN="$2"
            shift 2
            ;;
        --kernel-name)
            KERNEL_NAME="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            print_usage
            ;;
        *)
            ADDRESS_LINE="$1"
            shift
            ;;
    esac
done

if [[ -z "$KERNEL_NAME" || -z "$ADDRESS_LINE" ]]; then
    echo "Error: --kernel-name and an address line are required."
    print_usage
fi

# Paths
ADDR2LINE="$TOOLCHAIN_DIR/$TOOLCHAIN/bin/${TOOLCHAIN}-addr2line"
NM_TOOL="$TOOLCHAIN_DIR/$TOOLCHAIN/bin/${TOOLCHAIN}-nm"
VMLINUX_PATH="$KERNELS_DIR/$KERNEL_NAME/kernel/kernel/vmlinux"

# Verbose: Show paths
echo "Using addr2line tool: $ADDR2LINE"
echo "Using nm tool: $NM_TOOL"
echo "Using vmlinux file: $VMLINUX_PATH"
echo "Address line provided: $ADDRESS_LINE"

if [[ ! -x "$ADDR2LINE" ]]; then
    echo "Error: addr2line tool not found or not executable at $ADDR2LINE"
    exit 1
fi

if [[ ! -x "$NM_TOOL" ]]; then
    echo "Error: nm tool not found or not executable at $NM_TOOL"
    exit 1
fi

if [[ ! -f "$VMLINUX_PATH" ]]; then
    echo "Error: vmlinux not found at $VMLINUX_PATH"
    exit 1
fi

# Parse the function and offset
FUNCTION=$(echo "$ADDRESS_LINE" | grep -oP '[a-zA-Z0-9_.]+(?=\+0x)')
OFFSET=$(echo "$ADDRESS_LINE" | grep -oP '\+0x[0-9a-f]+')
if [[ -z "$FUNCTION" || -z "$OFFSET" ]]; then
    echo "Error: Failed to extract function and offset from the line: $ADDRESS_LINE"
    exit 1
fi
OFFSET=${OFFSET#+}  # Remove the leading '+'

echo "Extracted function: $FUNCTION"
echo "Extracted offset: $OFFSET"

# Find the base address of the function
BASE_ADDRESS=$("$NM_TOOL" "$VMLINUX_PATH" | grep " $FUNCTION" | awk '{print $1}')
if [[ -z "$BASE_ADDRESS" ]]; then
    echo "Error: Failed to find base address for function: $FUNCTION"
    exit 1
fi


# Calculate the absolute address using Python
ABSOLUTE_ADDRESS_HEX=$(python3 -c "
base_address = int('$BASE_ADDRESS', 16)
offset = int('$OFFSET', 16)
absolute_address = base_address + offset
print(f'0x{absolute_address:x}')
")

if [ $? -ne 0 ]; then
    echo "Error: Failed to calculate absolute address using Python."
    exit 1
fi

# Run addr2line
SOURCE_INFO=$("$ADDR2LINE" -e "$VMLINUX_PATH" "$ABSOLUTE_ADDRESS_HEX" 2>&1)

# Verbose: Show the raw output
echo "addr2line output:"

if [[ -z "$SOURCE_INFO" ]]; then
    echo "Error: Unable to resolve address 0x$(printf '%x' $ABSOLUTE_ADDRESS)."
    exit 1
fi

echo "Resolved source location: $SOURCE_INFO"

