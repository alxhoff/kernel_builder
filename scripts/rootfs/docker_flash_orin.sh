#!/usr/bin/env bash

set -euo pipefail

DOCKER_TAG="jetson-flasher-env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BSP_DIR="$SCRIPT_DIR/jetson_bsp"
ARCHIVE_NAME="jetson_bsp.tar.xz"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

# Check if Docker image exists
if [[ "$(docker images -q $DOCKER_TAG 2> /dev/null)" == "" ]]; then
    echo "[*] Building Docker image..."
    docker build -t $DOCKER_TAG - <<EOF
FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    sudo curl wget python3-pip unzip git \
    libxml2-utils binutils xz-utils dpkg-dev udev && \
    pip3 install gdown && \
    rm -rf /var/lib/apt/lists/*
EOF
else
    echo "[*] Docker image '$DOCKER_TAG' already exists, using it."
fi

# Download and extract BSP only if it doesn't exist
if [[ ! -d "$BSP_DIR" ]]; then
    echo "[*] BSP directory not found, downloading and extracting..."
    docker run --rm -it \
        -v "$SCRIPT_DIR":/workspace \
        -w /workspace \
        $DOCKER_TAG bash -c "\
            echo 'Please ensure you are logged into Google if needed.'; \
            gdown --fuzzy 'https://drive.google.com/uc?id=17npAsBctuCWB7PHwYnPJXW-8GVQvMKCg' -O $ARCHIVE_NAME; \
            mkdir -p jetson_bsp && \
            tar -xf $ARCHIVE_NAME -C jetson_bsp --strip-components=1"
else
    echo "[*] BSP already extracted in $BSP_DIR."
fi

# Run flash command inside container
docker run --rm -it \
    --privileged \
    -v /dev/bus/usb:/dev/bus/usb \
    -v "$BSP_DIR":/bsp \
    -w /bsp/Linux_for_Tegra \
    $DOCKER_TAG bash -c "echo '[*] Running cartken-flash...'; sudo ./cartken-flash orin"

