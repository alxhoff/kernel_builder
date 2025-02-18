#!/bin/bash

set -e  # Exit immediately on error

# Default values
BRANCH_NAME="v2.56.3-cartken"
INSTALL_DIR="$HOME/librealsense_cartken"
REPO_URL="https://gitlab.com/cartken/librealsense_cartken.git"

# Function to show help message
show_help() {
    echo "Usage: $0 <gitlab_access_token> [branch_name]"
    echo ""
    echo "Options:"
    echo "  <gitlab_access_token>   Required. GitLab personal access token for authentication."
    echo "  [branch_name]           Optional. Branch to clone (default: $BRANCH_NAME)."
    echo "  -h, --help              Show this help message."
    exit 0
}

# Check for help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
fi

# Validate input arguments
if [[ -z "$1" ]]; then
    echo "Error: GitLab access token is required."
    show_help
fi

GITLAB_ACCESS_TOKEN=$1
BRANCH_NAME=${2:-$BRANCH_NAME}  # Use provided branch name, or default to 'v2.56.3-cartken'
CLONE_URL="https://oauth2:${GITLAB_ACCESS_TOKEN}@gitlab.com/cartken/librealsense_cartken.git"

# Install dependencies
echo "Updating system and installing dependencies..."
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y git libssl-dev libusb-1.0-0-dev libudev-dev pkg-config libgtk-3-dev cmake
sudo apt-get install -y git wget cmake build-essential v4l-utils
sudo apt-get install -y libglfw3-dev libgl1-mesa-dev libglu1-mesa-dev at

# Clone the repository if it does not already exist
if [[ -d "$INSTALL_DIR" ]]; then
    echo "Skipping cloning: Repository already exists in $INSTALL_DIR."
else
    echo "Cloning repository from ${REPO_URL}..."
    if git clone --branch "$BRANCH_NAME" "$CLONE_URL" "$INSTALL_DIR"; then
        echo "Repository cloned successfully."
    else
        echo "Error: Failed to clone the repository. Please check your access token and branch name."
        exit 1
    fi
fi

# Navigate to the installation directory
cd "$INSTALL_DIR" || { echo "Error: Directory $INSTALL_DIR does not exist."; exit 1; }

# Set up udev rules
echo "Setting up udev rules..."
sudo ./scripts/setup_udev_rules.sh

# Create build directory
mkdir -p build && cd build

# Build the SDK
echo "Building the RealSense SDK..."
if cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_EXAMPLES=true && make -j$(nproc); then
    echo "Build completed successfully."
else
    echo "Error: Build failed."
    exit 1
fi

# Install the SDK
echo "Installing the RealSense SDK..."
if sudo make install; then
    echo "Installation completed successfully."
else
    echo "Error: Installation failed."
    exit 1
fi

echo "Intel RealSense SDK installation is complete."

