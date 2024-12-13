#!/bin/bash

# Function to display help
show_help() {
    echo "Usage: $(basename "$0") [OPTION]"
    echo ""
    echo "Automatically adds all untracked files in the current directory and subdirectories"
    echo "to a .gitignore file in the current working directory."
    echo ""
    echo "Options:"
    echo "  --help         Display this help message and exit."
    echo ""
    echo "Details:"
    echo "  - This script must be run inside a Git repository."
    echo "  - It scans for untracked files and directories using 'git ls-files --others --exclude-standard'."
    echo "  - The script appends untracked files to a .gitignore file in the directory where it is executed."
    echo "  - If a .gitignore file does not exist in the current directory, it will be created."
    echo "  - Duplicate entries in the .gitignore file will be removed automatically."
    echo ""
    echo "Example:"
    echo "  Run the script from the root of a Git repository to ignore all untracked files:"
    echo "    ./$(basename "$0")"
    echo ""
}

# Handle --help option
if [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# Ensure the script runs from the current working directory
current_dir=$(pwd)

# Check if we're in a git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: This is not a Git repository."
    exit 1
fi

# Get the list of untracked files
untracked_files=$(git ls-files --others --exclude-standard)

# Exit if there are no untracked files
if [ -z "$untracked_files" ]; then
    echo "No untracked files to add to .gitignore."
    exit 0
fi

# Path to the .gitignore file in the current working directory
gitignore_path="$current_dir/.gitignore"

# Add untracked files to .gitignore
echo "Adding untracked files to .gitignore:"
for file in $untracked_files; do
    echo "$file"
    echo "$file" >> "$gitignore_path"
done

# Remove duplicates in .gitignore
sort -u -o "$gitignore_path" "$gitignore_path"

echo "Untracked files have been added to .gitignore in $current_dir."

