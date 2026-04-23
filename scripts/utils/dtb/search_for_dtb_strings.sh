#!/bin/bash

# --- Configuration ---
# Exit immediately if a command exits with a non-zero status.
set -o errexit
# Treat unset variables as an error.
set -o nounset
# Pipelines fail if any command fails, not just the last one.
set -o pipefail

# --- Check for dependencies ---
if ! command -v dtc &> /dev/null; then
    echo "Error: 'dtc' (Device Tree Compiler) is not installed." >&2
    echo "On Debian/Ubuntu, install it with: sudo apt install device-tree-compiler" >&2
    exit 1
fi

# --- Validate Input ---
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 \"<search_string>\" [search_directory]" >&2
    echo "" >&2
    echo "  <search_string>:    The string to search for in decompiled .dtb files." >&2
    echo "  [search_directory]: (Optional) The directory to search in. Defaults to the current directory '.'." >&2
    exit 1
fi

SEARCH_STRING="$1"
# Default to current directory '.' if $2 is not provided or is empty.
SEARCH_DIR="${2:-.}"

# --- Create a single temporary file for decompilation ---
# We'll overwrite this file for each .dtb to save space and complexity.
# 'mktemp' creates a secure temp file and prints its path.
TEMP_DTS_FILE=""
TEMP_DTS_FILE=$(mktemp)

# --- Cleanup Trap ---
# This function will run on script exit (EXIT signal) or interrupt (INT, TERM),
# ensuring the temp file is always removed.
cleanup() {
    if [ -n "$TEMP_DTS_FILE" ]; then
        rm -f "$TEMP_DTS_FILE"
    fi
}
trap cleanup EXIT INT TERM

# --- Main Logic ---
echo "Searching for '$SEARCH_STRING' in .dtb files under '$SEARCH_DIR'..."
echo "---"

# We use find's -print0 and read's -d '' to robustly handle filenames
# that might contain spaces, newlines, or other special characters.
MATCH_COUNT=0
find "$SEARCH_DIR" -type f -name "*.dtb" -print0 | while IFS= read -r -d '' dtb_file; do

    # Decompile the .dtb file into our single temp .dts file.
    # -q suppresses non-error output.
    # We redirect stderr (2>/dev/null) to ignore errors from
    # potentially malformed or non-dtb files that end in .dtb.
    if ! dtc -q -I dtb -O dts -o "$TEMP_DTS_FILE" "$dtb_file" 2>/dev/null; then
        # If dtc fails, skip this file
        continue
    fi

    # Now, search the *content* of the decompiled temp file.
    # -q (quiet) exits immediately with status 0 if a match is found.
    # This is more efficient than reading the whole file.
    if grep -q "$SEARCH_STRING" "$TEMP_DTS_FILE"; then
        # If grep finds a match, print the *original* .dtb file path
        echo "$dtb_file"
        MATCH_COUNT=$((MATCH_COUNT + 1))
    fi

    # The loop continues, and TEMP_DTS_FILE is overwritten by the next dtc call
done

echo "---"
echo "Search complete. Found $MATCH_COUNT matching file(s)."

# The 'trap' will automatically call cleanup() now.
exit 0

