#!/usr/bin/env bash
set -e

# Ensure script is run with sudo/root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root (sudo)."
  exit 1
fi

# Install dependencies
apt-get update
apt-get install -y \
  libssl-dev libusb-1.0-0-dev libudev-dev pkg-config libgtk-3-dev \
  git wget cmake build-essential \
  libglfw3-dev libgl1-mesa-dev libglu1-mesa-dev at \
  libxrandr-dev

# Clone the repo if it doesn't exist, otherwise enter it
if [[ -d librealsense_cartken ]]; then
  cd librealsense_cartken
else
  git clone https://gitlab.com/cartken/librealsense_cartken.git
  cd librealsense_cartken
fi

# Checkout desired branch
git fetch
git checkout v2.56.4-cartken-metadata-d430-compat

# Create and enter build directory
mkdir -p build
cd build

# Build and install
cmake ..
make -j"$(nproc)"
make install

