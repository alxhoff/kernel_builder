#!/bin/bash

show_help() {
    echo "Usage: $0 [DIRECTORY]"
    echo
    echo "Find and list all 'tags' files in the specified directory and its subdirectories."
    echo
    echo "Options:"
    echo "  --help    Show this help message and exit"
    echo
    echo "Arguments:"
    echo "  DIRECTORY  The base directory to search (default is the current directory)"
    exit 0
}

find_ctags_files() {
    local base_dir="$1"

    if [[ ! -d "$base_dir" ]]; then
        echo "Error: Directory '$base_dir' does not exist." >&2
        exit 1
    fi

    echo "Searching for 'tags' files in '$base_dir'..."
    find "$base_dir" -type f -name "tags" -print
}

# Check for --help
if [[ "$1" == "--help" ]]; then
    show_help
fi

# Default to current directory if no argument is provided
base_dir="${1:-.}"

# Run the function
find_ctags_files "$base_dir"


