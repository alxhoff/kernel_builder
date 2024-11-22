#!/bin/bash

# Variables
IMAGE_NAME="stability-test-image"
CONTAINER_NAME="stability-test"
TAR_LOCATION="/xavier_ssd/stability-test.tar"
SSH_USER="root"
DRY_RUN=false

# Determine the script directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

# Get the device IP
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ "$#" -lt 1 ]; then
    echo "Usage: $0 [--create | --run | --remove | --logs | --help] [<device-ip>] [--dry-run]"
    exit 1
  fi
  DEVICE_IP=$1
fi

# SSH function to execute commands remotely
run_ssh() {
    ssh -t "${SSH_USER}@${DEVICE_IP}" "$@"
}

# Functions
show_help() {
    cat <<EOF
Usage: $0 [--create | --run | --remove | --logs | --help] [<device-ip>] [--dry-run]

Options:
  --create        Create the container (removes existing one if present).
  --run           Start the container, execute commands inside it, and run stability tests with serial numbers.
  --remove        Remove the container and image from the target device.
  --logs          Fetch and display the logs of the container.
  --help          Show this help message.
  --dry-run       Simulate the call to run_stability_test.py without executing it.

Notes:
  - The target device's IP can be stored in a file named 'device_ip' in the parent directory of this script.
  - Alternatively, provide the device IP as an argument.
EOF
}

import_image() {
    echo "Checking if image '$IMAGE_NAME' exists on target device..."
    if run_ssh "docker images --format '{{.Repository}}:{{.Tag}}' | grep -q '^${IMAGE_NAME}:latest\$'"; then
        echo "Image '$IMAGE_NAME' already exists on the target device."
    else
        echo "Image '$IMAGE_NAME' not found. Importing from $TAR_LOCATION..."

        # Check if the tar file exists on the target device
        if ! run_ssh "[ -f $TAR_LOCATION ]"; then
            echo "Error: Image tar file '$TAR_LOCATION' not found on the target device."
            exit 1
        fi

        # Import the tar file directly on the target device
        run_ssh "docker import $TAR_LOCATION $IMAGE_NAME" || {
            echo "Error: Failed to import image. Check the tar file and Docker logs."
            exit 1
        }
        echo "Image imported successfully."
    fi
}

create_container() {
    echo "Checking if container '$CONTAINER_NAME' exists on target device..."
    if run_ssh "docker ps -a --format '{{.Names}}' | grep -q '^${CONTAINER_NAME}\$'"; then
        echo "Container '$CONTAINER_NAME' already exists. Removing..."
        run_ssh "docker rm -f $CONTAINER_NAME" || {
            echo "Error: Failed to remove existing container."
            exit 1
        }
    fi

    echo "Creating container..."
    run_ssh "docker create -it \
        --name '$CONTAINER_NAME' \
        --runtime nvidia \
        --privileged \
        --network host \
        --workdir /home/ros/ \
        -v /dev:/dev \
        '$IMAGE_NAME' tail -f /dev/null" || {
            echo "Error: Failed to create container. Check the Docker logs on the target device."
            exit 1
        }
    echo "Container created."
}

run_container() {
    echo "Checking if container '$CONTAINER_NAME' exists on target device..."
    if ! run_ssh "docker ps -a --format '{{.Names}}' | grep -q '^${CONTAINER_NAME}\$'"; then
        echo "Container not found. Creating container..."
        import_image
        create_container
    fi

    echo "Starting container if stopped..."
    if ! run_ssh "docker ps --format '{{.Names}}' | grep -q '^${CONTAINER_NAME}\$'"; then
        run_ssh "docker start '$CONTAINER_NAME'" || {
            echo "Error: Failed to start container. Check the Docker logs on the target device."
            exit 1
        }
    fi

    echo "Running command to fetch serial numbers..."
    RS_FW_UPDATE_CMD="docker exec -it '$CONTAINER_NAME' rs-fw-update -l"
    echo "[Executing inside Docker]: $RS_FW_UPDATE_CMD"

    SERIALS=$(run_ssh "$RS_FW_UPDATE_CMD | grep -oP '(?<=s/n )[0-9]+' | tr '\n' ' '")
    if [ -z "$SERIALS" ]; then
        echo "Error: No serial numbers found."
        exit 1
    fi

    echo "Extracted serial numbers: $SERIALS"

    # Prepare the command for stability test
    STABILITY_TEST_CMD="docker exec -it '$CONTAINER_NAME' bash -c 'source /home/ros/install/setup.bash && python3 /home/ros/run_stability_test.py --serial-numbers $SERIALS'"
    echo "[Executing inside Docker]: $STABILITY_TEST_CMD"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] The following command would be executed inside the container:"
        echo "$STABILITY_TEST_CMD"
    else
        echo "Running stability tests with the serial numbers..."
        run_ssh "$STABILITY_TEST_CMD" || {
            echo "Error: Stability test execution failed."
            exit 1
        }
        echo "Stability tests completed successfully."
    fi
}

logs_container() {
    echo "Fetching logs for container '$CONTAINER_NAME'..."
    if run_ssh "docker ps -a --format '{{.Names}}' | grep -q '^${CONTAINER_NAME}\$'"; then
        run_ssh "docker logs '$CONTAINER_NAME'"
    else
        echo "Container '$CONTAINER_NAME' does not exist on the target device."
        echo "Hint: Ensure the container is created using '--create' or '--run' before fetching logs."
    fi
}

remove_container_and_image() {
    echo "Removing container and image from target device..."

    # Remove the container if it exists
    if run_ssh "docker ps -a --format '{{.Names}}' | grep -q '^${CONTAINER_NAME}\$'"; then
        echo "Removing container '$CONTAINER_NAME'..."
        run_ssh "docker rm -f $CONTAINER_NAME" || {
            echo "Error: Failed to remove container. Check Docker logs on the target device."
            exit 1
        }
    else
        echo "Container '$CONTAINER_NAME' does not exist."
    fi

    # Remove the image if it exists
    if run_ssh "docker images --format '{{.Repository}}' | grep -q '^${IMAGE_NAME}\$'"; then
        echo "Removing image '$IMAGE_NAME'..."
        run_ssh "docker rmi -f $IMAGE_NAME" || {
            echo "Error: Failed to remove image. Check Docker logs on the target device."
            exit 1
        }
    else
        echo "Image '$IMAGE_NAME' does not exist."
    fi

    echo "Cleanup complete."
}

# Parse options
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
    esac
done

# Main Script
case "$1" in
    --create)
        import_image
        create_container
        ;;
    --run)
        run_container
        ;;
    --remove)
        remove_container_and_image
        ;;
    --logs)
        logs_container
        ;;
    --help)
        show_help
        ;;
    *)
        echo "Invalid option: $1"
        show_help
        ;;
esac

