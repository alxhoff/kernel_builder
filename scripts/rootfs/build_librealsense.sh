#!/bin/bash

# Usage: ./install_realsense_sdk.sh <gitlab_access_token> [branch_name]
# Example: ./install_realsense_sdk.sh your_access_token v2.56.3-cartken

# Check if the GitLab access token is provided
if [ -z "$1" ]; then
    echo "Error: GitLab access token is required as the first argument."
    exit 1
fi

# Assign variables
GITLAB_ACCESS_TOKEN=$1
BRANCH_NAME=${2:-v2.56.3-cartken}  # Default to 'v2.56.3-cartken' if no branch is specified
REPO_URL="https://gitlab.com/cartken/librealsense_cartken.git"
CLONE_URL="https://oauth2:${GITLAB_ACCESS_TOKEN}@gitlab.com/cartken/librealsense_cartken.git"
INSTALL_DIR="$HOME/librealsense_cartken"

# Update and install required dependencies
echo "Updating system and installing dependencies..."
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y git libssl-dev libusb-1.0-0-dev libudev-dev pkg-config libgtk-3-dev cmake

# Clone the repository
echo "Cloning the repository from ${REPO_URL}..."
if git clone --branch "$BRANCH_NAME" "$CLONE_URL" "$INSTALL_DIR"; then
    echo "Repository cloned successfully."
else
    echo "Error: Failed to clone the repository. Please check your access token and branch name."
    exit 1
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

