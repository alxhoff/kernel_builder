#!/bin/bash

# Ensure the script is run with sudo
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run with sudo."
    exit 1
fi

# Get the directory of the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set variables
IMAGE="ubuntu:22.04"
CONTAINER_NAME="tegra_setup"
SCRIPT_NAME="setup_tegra_package.sh"

# Function to show help
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -j, --jetpack VERSION   Specify JetPack version (default: 5.1.3)"
    echo "  --access-token TOKEN     Provide the access token (required)"
    echo "  --tag TAG                Specify tag for get_packages.sh (default: latest)"
    echo "  --soc SOC                Specify SoC type for jetson_chroot.sh (default: unspecified)"
    echo "                         Available versions: 5.1.3 (L4T <L4T_VERSION_5.1.3>), 5.1.2 (L4T <L4T_VERSION_5.1.2>)"
    echo "  --no-download           Use existing .tbz2 files instead of downloading"
    echo "  -h, --help              Show this help message"
    exit 0
}

# Check if --help is passed
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
fi

# Get the real user details
HOST_USER=$(logname 2>/dev/null || echo $SUDO_USER)
HOST_UID=$(id -u $HOST_USER)
HOST_GID=$(id -g $HOST_USER)

# Pull the latest Ubuntu 22.04 image
docker pull $IMAGE

# Run the script inside a privileged container with the user setup
docker run --rm -it \
    --name $CONTAINER_NAME \
    --privileged \
    -v "$SCRIPT_DIR:$SCRIPT_DIR" \
    -w "$SCRIPT_DIR" \
    -e HOME="$SCRIPT_DIR" \
    -e LOGNAME="$HOST_USER" \
    -e USER="$HOST_USER" \
    $IMAGE \
    /bin/bash -c "
        apt-get update && apt-get install -y sudo tar bzip2 git wget curl jq qemu-user-static unzip build-essential && \
		apt-get install -y flex bison libssl-dev libelf-dev bc dwarves ccache libncurses5-dev vim-common && \
        groupadd --gid $HOST_GID $HOST_USER && \
        useradd --uid $HOST_UID --gid $HOST_GID --home $SCRIPT_DIR --shell /bin/bash $HOST_USER && \
        echo '$HOST_USER ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers && \
        su - $HOST_USER -c 'sudo ./setup_tegra_package.sh $*'
    "

