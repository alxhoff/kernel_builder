#!/bin/bash

# Set the image name and default container name
IMAGE_NAME="ubuntu20.04-basic"
CONTAINER_NAME=${2:-ubuntu20.04-container} # Optional container name

# Function to display help
show_help() {
    cat <<EOF
Usage: $0 [options] <folder_to_mount> [container_name]

Options:
  --help       Show this help message and exit.
  --rebuild    Force rebuild of the Docker image using the existing Dockerfile.

Description:
  This script is used to run a Docker container based on an Ubuntu 20.04 image.
  If the Docker image '$IMAGE_NAME' does not exist, the script will automatically
  build it using the Dockerfile in the current directory. The --rebuild option
  allows you to force a rebuild of the image.

Arguments:
  <folder_to_mount>   The path to a folder on the host machine that will be
                      mounted inside the container at /workspace/mounted_folder.
  [container_name]    (Optional) The name of the container. If not specified,
                      defaults to '$CONTAINER_NAME'.

Steps performed by this script:
  1. Checks if the specified Docker image exists. If not, builds it from the
     Dockerfile in the current directory.
  2. Verifies that the folder specified as <folder_to_mount> exists on the host.
  3. Runs the Docker container with the specified folder mounted.

Examples:
  To run the container with a mounted folder:
    $0 /path/to/host/folder

  To run the container with a custom container name:
    $0 /path/to/host/folder my_custom_container

  To force a rebuild of the Docker image:
    $0 --rebuild /path/to/host/folder

Notes:
  - Ensure that the Dockerfile is present in the current directory for the
    script to build the image if needed or when using --rebuild.
  - You must have Docker installed and configured on your system.
  - The script must be run with sufficient privileges to access Docker
    (e.g., as a user in the 'docker' group or as root).

EOF
}

# Function to build the Docker image
build_image() {
    echo "Building the Docker image '$IMAGE_NAME'..."
    if [ -f Dockerfile ]; then
        docker build -t "$IMAGE_NAME" .
        echo "Image '$IMAGE_NAME' built successfully."
    else
        echo "Error: Dockerfile not found in the current directory."
        exit 1
    fi
}

# Function to ensure the Docker image exists
build_image_if_needed() {
    if ! docker image inspect "$IMAGE_NAME" > /dev/null 2>&1; then
        echo "Docker image '$IMAGE_NAME' not found. Building the image..."
        build_image
    fi
}

# Check for options
REBUILD=false
if [ "$1" == "--help" ]; then
    show_help
    exit 0
elif [ "$1" == "--rebuild" ]; then
    REBUILD=true
    shift  # Shift arguments to process <folder_to_mount>
fi

# Check if at least one argument is provided
if [ "$#" -lt 1 ]; then
    echo "Error: Missing arguments."
    echo "Use --help for usage instructions."
    exit 1
fi

# Get the folder to mount
HOST_FOLDER=$1

# Check if the folder exists
if [ ! -d "$HOST_FOLDER" ]; then
    echo "Error: Folder $HOST_FOLDER does not exist."
    exit 1
fi

# Build or rebuild the Docker image if necessary
if $REBUILD; then
    echo "Forcing rebuild of the Docker image..."
    build_image
else
    build_image_if_needed
fi

# Run the Docker container
echo "Running Docker container '$CONTAINER_NAME' with volume mounted from '$HOST_FOLDER'..."
docker run -it --rm --privileged \
    -v "$HOST_FOLDER:/workspace/mounted_folder" \
    --name "$CONTAINER_NAME" \
    "$IMAGE_NAME"

