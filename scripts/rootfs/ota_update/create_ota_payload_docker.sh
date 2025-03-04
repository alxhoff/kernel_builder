#!/bin/bash

set -e

# Default values
BASE_BSP=""
TARGET_BSP=""
PARTITION_XML=""
FORCE_PARTITION_CHANGE=false
REBUILD_IMAGE=false
IMAGE_NAME="jetson-ota-builder:latest"

# Function to show help
show_help() {
    echo "Usage: $0 --base-bsp <path> --target-bsp <path> --partition-xml <file> [--force-partition-change] [--rebuild]"
    echo "Options:"
    echo "  --base-bsp PATH              Path to the BASE BSP source (e.g., 5.1.2)"
    echo "  --target-bsp PATH            Path to the TARGET BSP source (e.g., 5.1.3)"
    echo "  --partition-xml FILE         Path to a partition XML file"
    echo "  --force-partition-change     Enable forced partition change during OTA payload generation"
    echo "  --rebuild                    Force rebuild of the Docker image"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-bsp)
            BASE_BSP=$(realpath "$2")
            shift 2
            ;;
        --target-bsp)
            TARGET_BSP=$(realpath "$2")
            shift 2
            ;;
        --partition-xml)
            PARTITION_XML=$(realpath "$2")
            shift 2
            ;;
        --force-partition-change)
            FORCE_PARTITION_CHANGE=true
            shift
            ;;
        --rebuild)
            REBUILD_IMAGE=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Validate required parameters
if [[ -z "$BASE_BSP" || -z "$TARGET_BSP" || -z "$PARTITION_XML" ]]; then
    echo "Error: --base-bsp, --target-bsp, and --partition-xml must be provided."
    exit 1
fi

# Check if the image exists
if [[ "$REBUILD_IMAGE" == true ]] || ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "Building Docker image..."
    docker build -t "$IMAGE_NAME" - <<EOF
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y apt-utils && \
    apt-get install -y wget tar sudo bash libxml2-utils cpio binutils \
    openssh-client dosfstools util-linux device-tree-compiler python3 \
    python3-pip bc bzip2 xz-utils kmod qemu-user-static \
    pv zip unzip git curl libssl-dev rsync jq \
    && apt-get clean
RUN pip3 install --no-cache-dir pyyaml
RUN ln -s $(which python3) /usr/bin/python
WORKDIR /workspace
EOF
else
    echo "Using existing Docker image: $IMAGE_NAME"
fi

# Run the script inside the container
docker run --rm -it --privileged \
    --device /dev/loop-control \
    --device /dev/loop0:/dev/loop0 \
    --device /dev/loop1:/dev/loop1 \
    -v "$(dirname "$BASE_BSP"):/workspace/base_bsp" \
    -v "$(dirname "$TARGET_BSP"):/workspace/target_bsp" \
    -v "$(dirname "$PARTITION_XML"):/workspace/xml" \
    -v "$(pwd):/workspace/script" \
    "$IMAGE_NAME" \
    bash -c "
    cd /workspace/script && \
    sudo ./create_ota_payload.sh \
        --base-bsp /workspace/base_bsp/$(basename "$BASE_BSP") \
        --target-bsp /workspace/target_bsp/$(basename "$TARGET_BSP") \
        --partition-xml /workspace/xml/$(basename "$PARTITION_XML") \
        $(if $FORCE_PARTITION_CHANGE; then echo '--force-partition-change'; fi)
    "

echo "OTA payload generation completed."

