#!/bin/bash

# Check if dtc is installed
if ! command -v dtc &> /dev/null; then
    echo "Error: dtc (Device Tree Compiler) is not installed."
    echo "Install it using your package manager (e.g., apt, pacman)."
    exit 1
fi

# Function to display help message
show_help() {
    cat << EOF
Usage: $0 --decompile <path_to_dtb> | --recompile <path_to_dts> | --help

Options:
  --decompile    Decompile a Device Tree Blob (.dtb) file into a Device Tree Source (.dts) file.
  --recompile    Recompile a Device Tree Source (.dts) file back into a Device Tree Blob (.dtb) file.
  --help         Show this help message with examples.

Examples:
  To decompile a .dtb file into a .dts file:
    $0 --decompile /path/to/file.dtb

  To recompile a .dts file into a .dtb file:
    $0 --recompile /path/to/file.dts

Details:
  1. The output file is saved in the same directory as the script.
  2. The output file has the same name as the input file but with the appropriate extension (.dts or .dtb).
  3. Ensure that the 'dtc' tool (Device Tree Compiler) is installed on your system.

EOF
}

# Check if at least one argument is provided
if [ "$#" -lt 1 ]; then
    show_help
    exit 1
fi

# Parse the arguments
ACTION="$1"
FILE_PATH="${2:-}"

if [[ "$ACTION" == "--help" ]]; then
    show_help
    exit 0
fi

if [[ -z "$FILE_PATH" ]]; then
    echo "Error: Missing file argument."
    show_help
    exit 1
fi

# Ensure the input file exists
if [ ! -f "$FILE_PATH" ]; then
    echo "Error: File $FILE_PATH not found."
    exit 1
fi

# Get the directory where the script is located
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# Perform the appropriate action
case "$ACTION" in
    --decompile)
        # Decompile .dtb to .dts
		if [[ "$FILE_PATH" != *.dtb && "$FILE_PATH" != *.dtbo ]]; then
            echo "Error: Input file must have a .dtb extension for decompilation."
            exit 1
        fi

        FILENAME=$(basename "$FILE_PATH" .dtb)
        OUTPUT_DTS="$SCRIPT_DIR/$FILENAME.dts"

        dtc -I dtb -O dts -o "$OUTPUT_DTS" "$FILE_PATH"
        if [ $? -eq 0 ]; then
            echo "Successfully decompiled $FILE_PATH to $OUTPUT_DTS"
        else
            echo "Error: Failed to decompile $FILE_PATH."
            exit 1
        fi
        ;;

    --recompile)
        # Recompile .dts to .dtb
        if [[ "$FILE_PATH" != *.dts ]]; then
            echo "Error: Input file must have a .dts extension for recompilation."
            exit 1
        fi

        FILENAME=$(basename "$FILE_PATH" .dts)
        OUTPUT_DTB="$SCRIPT_DIR/$FILENAME.dtb"

        dtc -I dts -O dtb -o "$OUTPUT_DTB" "$FILE_PATH"
        if [ $? -eq 0 ]; then
            echo "Successfully recompiled $FILE_PATH to $OUTPUT_DTB"
        else
            echo "Error: Failed to recompile $FILE_PATH."
            exit 1
        fi
        ;;

    *)
        echo "Error: Invalid action. Use --decompile, --recompile, or --help."
        show_help
        exit 1
        ;;
esac

