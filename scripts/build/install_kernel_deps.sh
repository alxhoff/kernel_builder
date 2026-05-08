#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

echo "Updating package list..."
sudo apt update

echo "Installing required packages for Linux kernel building..."
sudo apt install -y \
    build-essential \
    flex \
    bison \
    libssl-dev \
    libelf-dev \
    bc \
    dwarves \
    ccache \
    libncurses5-dev \
    libncursesw5-dev \
    vim-common \
    git \
    curl \
    wget \
    jq

echo "All required packages installed successfully!"

