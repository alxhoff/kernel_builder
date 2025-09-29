#!/bin/bash

# Ensure the script is run with sudo
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run with sudo."
    exit 1
fi

# --- Host Dependency Installation ---
echo "Checking for and installing host dependencies for cross-architecture container support..."

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
else
    echo "Cannot determine the operating system."
    exit 1
fi

# Install dependencies based on OS
if [[ "$OS" == "Ubuntu" || "$OS" == "Debian GNU/Linux" ]]; then
    if ! dpkg -l | grep -q "qemu-user-static" || ! dpkg -l | grep -q "binfmt-support"; then
        echo "Installing QEMU and binfmt support for Debian/Ubuntu..."
        apt-get update
        apt-get install -y qemu-user-static binfmt-support
    else
        echo "QEMU and binfmt support are already installed."
    fi
elif [[ "$OS" == "Arch Linux" || "$OS" == "Manjaro Linux" ]]; then
    if ! pacman -Q | grep -q "qemu-user-static" || ! pacman -Q | grep -q "binfmt-support"; then
        echo "Installing QEMU and binfmt support for Arch Linux..."
        pacman -Syu --noconfirm qemu-user-static binfmt-support
    else
        echo "QEMU and binfmt support are already installed."
    fi
else
    echo "Unsupported operating system: $OS"
    exit 1
fi

# Register QEMU handlers with the kernel
# This is crucial for running ARM64 binaries inside the x86 container
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes > /dev/null

# Get the directory of the script
SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"

# Set variables
IMAGE="ubuntu:22.04"
CONTAINER_NAME="tegra_setup"
DOCKER_TAG="$CONTAINER_NAME:latest"
SCRIPT_NAME="setup_tegra_package.sh"
RUN_SETUP_SCRIPT=true

# Function to show help
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --inspect               Start a shell inside the container without running the setup script"
    echo "  -h, --help              Show this help message"
    exit 0
}

# Parse arguments
for arg in "$@"; do
    case $arg in
        --inspect)
            RUN_SETUP_SCRIPT=false
            shift
            ;;
        --rebuild)
            REBUILD=true
            shift
            ;;
        --help|-h)
            show_help
            ;;
    esac
done

if [[ "$RUN_SETUP_SCRIPT" == true ]]; then
    CONTAINER_CMD="./setup_tegra_package.sh $@"
else
    CONTAINER_CMD="/bin/bash"
fi

if [[ "$(docker images -q "$DOCKER_TAG" 2> /dev/null)" == "" || "$REBUILD" == true ]]; then
    echo "Building or rebuilding the Docker image..."
	docker pull "$IMAGE"
    docker build -t "$DOCKER_TAG" - <<EOF
    FROM $IMAGE
    RUN apt-get update && apt-get install -y sudo tar bzip2 git wget curl
	RUN apt-get update && apt-get install -y jq qemu-user-static binfmt-support
	RUN apt-get update && apt-get install -y unzip build-essential kmod flex bison
	RUN apt-get update && apt-get install -y libelf-dev bc dwarves ccache libncurses5-dev
	RUN apt-get update && apt-get install -y vim-common rsync zlib1g libssl-dev
EOF
else
    echo "Using existing Docker image: $DOCKER_TAG"
fi

if docker ps -a --format '{{.Names}}' | grep -qw "$CONTAINER_NAME"; then
    echo "Removing existing container: $CONTAINER_NAME"
    docker rm -f "$CONTAINER_NAME"
fi

docker run --rm -i \
    --name "$CONTAINER_NAME" \
    --privileged \
    --network=host \
    -v "$SCRIPT_DIR:/workspace" \
    -w "/workspace" \
    -e HOME="/workspace" \
    "$DOCKER_TAG" \
    /bin/bash -c "$CONTAINER_CMD"