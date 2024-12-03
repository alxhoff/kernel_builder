#!/bin/bash

# Check if dtc is installed
if ! command -v dtc &> /dev/null; then
    echo "Error: dtc (Device Tree Compiler) is not installed."
    echo "Install it using your package manager (e.g., apt, pacman)."
    exit 1
fi

# Check if an argument is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path_to_dtb>"
    exit 1
fi

# Get the full path of the input .dtb file
DTB_PATH="$1"

# Ensure the input file exists
if [ ! -f "$DTB_PATH" ]; then
    echo "Error: File $DTB_PATH not found."
    exit 1
fi

# Get the directory where the script is located
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# Extract the filename without extension
FILENAME=$(basename "$DTB_PATH" .dtb)

# Define the output .dts path in the script's directory
OUTPUT_DTS="$SCRIPT_DIR/$FILENAME.dts"

# Convert the .dtb to .dts
dtc -I dtb -O dts -o "$OUTPUT_DTS" "$DTB_PATH"

if [ $? -eq 0 ]; then
    echo "Successfully converted $DTB_PATH to $OUTPUT_DTS"
else
    echo "Error: Failed to convert $DTB_PATH to DTS."
    exit 1
fi

