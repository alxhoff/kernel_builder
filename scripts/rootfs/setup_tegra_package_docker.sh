#!/bin/bash

# Ensure the script is run with sudo
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run with sudo."
    exit 1
fi

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
    CONTAINER_CMD="./setup_tegra_package.sh $*"
else
    CONTAINER_CMD="/bin/bash"
fi

if [[ "$(docker images -q "$DOCKER_TAG" 2> /dev/null)" == "" || "$REBUILD" == true ]]; then
    echo "Building or rebuilding the Docker image..."
	docker pull "$IMAGE"
    docker build -t "$DOCKER_TAG" - <<EOF
    FROM $IMAGE
    RUN apt-get update && \
        apt-get install -y sudo tar bzip2 git wget curl jq qemu-user-static unzip build-essential kmod && \
        apt-get install -y flex bison libssl-dev libelf-dev bc dwarves ccache libncurses5-dev vim-common
EOF
else
    echo "Using existing Docker image: $DOCKER_TAG"
fi

if docker ps -a --format '{{.Names}}' | grep -qw "$CONTAINER_NAME"; then
    echo "Removing existing container: $CONTAINER_NAME"
    docker rm -f "$CONTAINER_NAME"
fi

docker run --rm -it \
    --name "$CONTAINER_NAME" \
    --privileged \
    --network=host \
    -v "$SCRIPT_DIR:$SCRIPT_DIR" \
    -w "$SCRIPT_DIR" \
    -e HOME="$SCRIPT_DIR" \
    "$DOCKER_TAG" \
    /bin/bash -c "$CONTAINER_CMD"

