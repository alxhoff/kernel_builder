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

REBUILD=0
DOCKER_DATA=""
INSPECT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --l4t-version)
            shift
            L4T_VERSION="$1"
            ;;
        --rebuild)
            REBUILD=1
            ;;
        --docker-data)
            shift
            DOCKER_DATA="$1"
            ;;
        --inspect)
            INSPECT=1
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
    shift
done

# Ensure Docker is installed and ready
if ! command -v docker &> /dev/null; then
    echo "[*] Docker not found. Installing..."
    sudo apt-get update
	sudo apt-get install -y \
    ca-certificates curl gnupg lsb-release

	sudo mkdir -p /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
		sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

	echo \
	  "deb [arch=$(dpkg --print-architecture) \
	  signed-by=/etc/apt/keyrings/docker.gpg] \
	  https://download.docker.com/linux/ubuntu \
	  $(lsb_release -cs) stable" | \
	  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

	sudo apt-get update
	sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    sudo systemctl enable docker
fi

if [[ -n "$DOCKER_DATA" ]]; then
    echo "[*] Configuring Docker to use data directory: $DOCKER_DATA/docker"
    systemctl stop docker
    mkdir -p "$DOCKER_DATA/docker"
    if [[ -d /var/lib/docker && ! -L /var/lib/docker ]]; then
        mv /var/lib/docker "$DOCKER_DATA/docker"
    fi
    mkdir -p /etc/docker
    echo "{\"data-root\": \"$DOCKER_DATA/docker\"}" > /etc/docker/daemon.json
    systemctl daemon-reexec
    echo "[*] Docker data root updated."
fi

# Ensure Docker service is running
if ! systemctl is-active --quiet docker; then
    echo "[*] Starting Docker service..."
    sudo systemctl start docker
fi

# Add current user to docker group if not already
if ! groups "$USER" | grep -q '\bdocker\b'; then
    echo "[*] Adding user '$USER' to docker group. You may need to re-login."
    sudo usermod -aG docker "$USER"
fi

# Check if Docker image exists
if [[ "$REBUILD" -eq 1 || "$(docker images -q $DOCKER_TAG 2> /dev/null)" == "" ]]; then
    echo "[*] Building Docker image (rebuild=${REBUILD})..."
	if [[ $REBUILD -eq 1 ]]; then
		echo "[*] Cleaning up old Docker images and containers..."
		docker container prune -f || true
		docker image prune -a -f || true
		docker rmi -f $DOCKER_TAG || true
		echo "[*] Removing all Docker containers and volumes..."
		docker rm -f $(docker ps -aq) 2>/dev/null || true
		docker volume prune -f || true
	fi
    docker build --no-cache -t $DOCKER_TAG - <<EOF
FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    sudo curl wget python3-pip unzip git usbutils cpio \
    libxml2-utils binutils xz-utils dpkg-dev udev && \
    pip3 install gdown pyyaml && \
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
            tar -xf $ARCHIVE_NAME -C jetson_bsp --strip-components=1 && \
			rm -f $ARCHIVE_NAME"
else
    echo "[*] BSP already extracted in $BSP_DIR."
fi

if [[ "$INSPECT" -eq 1 ]]; then
    echo "[*] Dropping into interactive shell inside Docker..."
    docker run --rm -it \
        --privileged \
        -v /dev/bus/usb:/dev/bus/usb \
        -v "$BSP_DIR":/bsp \
        -w /bsp/Linux_for_Tegra \
        $DOCKER_TAG bash
else
    # Run flash command inside container
    docker run --rm -it \
        --privileged \
        -v /dev/bus/usb:/dev/bus/usb \
        -v "$BSP_DIR":/bsp \
        -w /bsp/Linux_for_Tegra \
        $DOCKER_TAG bash -c "echo '[*] Running cartken-flash...'; sudo ./cartken-flash orin"
fi

