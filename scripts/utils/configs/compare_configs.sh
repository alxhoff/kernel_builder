#!/bin/bash

# ---
# A bash script to compare two Linux .config files and show the differences.
#
# Usage: ./compare_configs.sh <path/to/config1> <path/to/config2>
#
# It treats options that are missing or explicitly commented out
# (e.g., "# CONFIG_FOO is not set") as "not set".
# ---

# Check for bash version (need 4.0+ for associative arrays)
if ((BASH_VERSINFO[0] < 4)); then
    echo "Error: This script requires bash version 4.0 or higher." >&2
    exit 1
fi

# --- Argument Validation ---
if [[ "$#" -ne 2 ]]; then
    echo "Usage: $0 <config_file_1> <config_file_2>" >&2
    echo "Example: $0 config-5.15.0 config-5.18.0" >&2
    exit 1
fi

FILE1="$1"
FILE2="$2"

if [[ ! -f "$FILE1" ]]; then
    echo "Error: File not found: $FILE1" >&2
    exit 1
fi
if [[ ! -f "$FILE2" ]]; then
    echo "Error: File not found: $FILE2" >&2
    exit 1
fi

# --- Helper Function ---

# Parses a .config file into a bash associative array.
# Usage: parse_config "filename" assoc_array_name
parse_config() {
    local file="$1"
    # Pass array by reference (nameref)
    local -n map=$2

    # Clear the map to ensure it's empty
    map=()

    # Read the file line by line
    # We use 'while IFS= read -r line || [[ -n "$line" ]]' to correctly
    # read the last line even if it doesn't have a trailing newline.
    while IFS= read -r line || [[ -n "$line" ]]; do

        # Match explicit 'not set'
        # e.g., # CONFIG_FOO is not set
        if [[ "$line" =~ ^#\ (CONFIG_[A-Za-z0-9_]+)\ is\ not\ set ]]; then
            map["${BASH_REMATCH[1]}"]="not set"

        # Match set values
        # e.g., CONFIG_FOO=y
        # e.g., CONFIG_BAR="baz"
        # e.g., CONFIG_NUM=123
        elif [[ "$line" =~ ^(CONFIG_[A-Za-z0-9_]+)=(.*) ]]; then
            map["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
        fi

        # Other lines (empty, comments, etc.) are ignored.

    done < "$file"
}

# --- Main Script ---

# Declare the associative arrays
declare -A config1_map
declare -A config2_map

# Parse both files into their respective maps
parse_config "$FILE1" config1_map
parse_config "$FILE2" config2_map

# Get all unique keys from both maps.
# 1. Print all keys from both maps, each on a new line.
# 2. Sort them and get only the unique keys.
all_keys=$( (printf "%s\n" "${!config1_map[@]}" "${!config2_map[@]}") | sort -u)

# --- Print Comparison ---

# Get just the filenames for the header
F1_NAME=$(basename "$FILE1")
F2_NAME=$(basename "$FILE2")

# Print the header
printf "%-45s | %-25s | %-25s\n" "CONFIG OPTION" "$F1_NAME" "$F2_NAME"
printf "%s\n" "------------------------------------------------------------------------------------------------------"

# Iterate over all unique keys and compare values
for key in $all_keys; do
    # Get values from each map.
    # If the key doesn't exist in the map (i.e., it was missing from the file),
    # the ':-"not set"' expansion provides a default value.
    val1=${config1_map[$key]:-"not set"}
    val2=${config2_map[$key]:-"not set"}

    # If the values are different, print the line
    if [[ "$val1" != "$val2" ]]; then
        printf "%-45s | %-25s | %-25s\n" "$key" "$val1" "$val2"
    fi
done

