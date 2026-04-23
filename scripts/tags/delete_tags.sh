#!/bin/bash

# Script to recursively delete all 'tags' files in a given directory and its subdirectories.

# Function to show usage
show_help() {
    echo "Usage: $0 <directory>"
    echo
    echo "Options:"
    echo "  <directory>      The target directory to search and delete 'tags' files."
    echo "  -h, --help       Show this help message."
    echo
    echo "Examples:"
    echo "  $0 /path/to/directory        Deletes all 'tags' files in the specified directory."
    echo "  $0 ~/projects/my_kernel      Deletes all 'tags' files in the 'my_kernel' directory."
    exit 0
}

# Check if arguments are provided
if [[ $# -eq 0 ]]; then
    echo "Error: No arguments provided."
    show_help
fi

# Parse arguments
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
fi

TARGET_DIR="$1"

# Validate the directory
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: '$TARGET_DIR' is not a valid directory."
    exit 1
fi

# Find and delete all 'tags' files
echo "Searching for 'tags' files in '$TARGET_DIR'..."
find "$TARGET_DIR" -type f -name "tags" -exec rm -v {} \;

echo "All 'tags' files deleted from '$TARGET_DIR'."

