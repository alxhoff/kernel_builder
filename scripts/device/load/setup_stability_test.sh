#!/bin/bash

set -e  # Exit immediately on error

IMAGE_TAR="stability-test.tar"
IMAGE_NAME="stability-test-image"
CONTAINER_NAME="stability-test"
WORKDIR="/home/ros/"
STABILITY_TEST_SCRIPT="/home/ros/stability_test.sh"  # Modify if needed

# Function to show usage
show_help() {
    echo "Usage: $0 [--shell | --test]"
    echo "Options:"
    echo "  --shell     Drop into an interactive bash shell inside the container (keeps changes)."
    echo "  --test      Run the stability test script inside the container."
    exit 0
}

# Parse arguments
if [[ $# -eq 0 ]]; then
    show_help
fi

MODE=""
case "$1" in
    --shell)
        MODE="shell"
        ;;
    --test)
        MODE="test"
        ;;
    -h|--help)
        show_help
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        ;;
esac

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Installing Docker..."

    # Install dependencies
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release nvidia-container-toolkit

    # Install Docker
    sudo apt-get update
    sudo apt-get install -y nvidia-docker2

    # Enable and start Docker service
    sudo systemctl enable docker
    sudo systemctl start docker

    # Add user to Docker group
    sudo usermod -aG docker $USER
    echo "Docker installed successfully. You may need to log out and log back in for group changes to take effect."
else
    echo "Docker is already installed."
fi

# Ensure the user is in the Docker group
if ! groups | grep -q "docker"; then
    echo "Warning: You are not in the docker group. Running commands with sudo..."
    DOCKER_CMD="sudo docker"
else
    DOCKER_CMD="docker"
fi

# Import the Docker image if not already imported
if ! $DOCKER_CMD image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "Importing Docker image from $IMAGE_TAR..."
    $DOCKER_CMD import "$IMAGE_TAR" "$IMAGE_NAME"
    echo "Docker image imported successfully."
fi

# Check if the container exists, if not, create it
if ! $DOCKER_CMD ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
    echo "Creating container '$CONTAINER_NAME'..."
    $DOCKER_CMD create -it --name "$CONTAINER_NAME" --runtime nvidia --privileged --network host \
        --workdir "$WORKDIR" -v /dev:/dev "$IMAGE_NAME" bash
    echo "Container created successfully."
fi

# Start the container if it's not running
if ! $DOCKER_CMD ps --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
    echo "Starting container '$CONTAINER_NAME'..."
    $DOCKER_CMD start "$CONTAINER_NAME"
fi

# Choose mode: shell or test
if [[ "$MODE" == "shell" ]]; then
    echo "Dropping into an interactive bash shell inside the container..."
    $DOCKER_CMD exec -it "$CONTAINER_NAME" bash

    # After exiting shell, commit changes
    echo "Committing changes to Docker image..."
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    NEW_IMAGE_NAME="${IMAGE_NAME}-modified-${TIMESTAMP}"
    $DOCKER_CMD commit "$CONTAINER_NAME" "$NEW_IMAGE_NAME"
    echo "Changes saved as new image: $NEW_IMAGE_NAME"

elif [[ "$MODE" == "test" ]]; then
    echo "Running stability test script inside the container..."
    $DOCKER_CMD exec -it "$CONTAINER_NAME" bash -c "$STABILITY_TEST_SCRIPT"
else
    echo "Invalid mode. Exiting."
    exit 1
fi

