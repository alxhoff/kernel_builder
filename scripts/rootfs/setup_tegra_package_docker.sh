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
        --help|-h)
            show_help
            ;;
    esac
done

# Pull the latest Ubuntu 22.04 image
docker pull "$IMAGE"

# Determine the command to run inside the container
if [[ "$RUN_SETUP_SCRIPT" == true ]]; then
    CONTAINER_CMD="./setup_tegra_package.sh $*"
else
    CONTAINER_CMD="/bin/bash"
fi

# Run the script inside a privileged container as root
docker run --rm -it \
    --name "$CONTAINER_NAME" \
    --privileged \
    --network=host \
    -v "$SCRIPT_DIR:$SCRIPT_DIR" \
    -w "$SCRIPT_DIR" \
    -e HOME="$SCRIPT_DIR" \
    "$IMAGE" \
    /bin/bash -c "
        apt-get update && \
        apt-get install -y sudo tar bzip2 git wget curl jq qemu-user-static unzip build-essential kmod && \
        apt-get install -y flex bison libssl-dev libelf-dev bc dwarves ccache libncurses5-dev vim-common

        exec $CONTAINER_CMD
    "

