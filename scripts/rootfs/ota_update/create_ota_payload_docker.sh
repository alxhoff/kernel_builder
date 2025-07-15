#!/bin/bash

set -e

# Default values
BASE_BSP=""
TARGET_BSP=""
PARTITION_XML=""
FORCE_PARTITION_CHANGE=false
REBUILD_IMAGE=false
IMAGE_NAME="jetson-ota-builder:latest"
BUILD_BOOTLOADER=false
BUILD_ROOTFS=false
SKIP_BUILD=false


# Function to show help
show_help() {
    echo "Usage: $0 --base-bsp <path> --target-bsp <path> --partition-xml <file> [--force-partition-change] [--rebuild]"
    echo "Options:"
    echo "  --base-bsp PATH              Path to the BASE BSP source (e.g., 5.1.2)"
    echo "  --target-bsp PATH            Path to the TARGET BSP source (e.g., 5.1.3)"
    echo "  --partition-xml FILE         Path to a partition XML file"
    echo "  --force-partition-change     Enable forced partition change during OTA payload generation"
    echo "  --rebuild                    Force rebuild of the Docker image"
	echo "  --deploy IP					 Deploys the ota payload to a target device"
	echo "  --skip-build				 Skips the generation of the OTA package (assumes it exists already)"
	echo "  -b                           Build only the bootloader"
    echo "  -r                           Build only the rootfs"
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
		--deploy)
            DEPLOY_IP="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
		--inspect)
            INSPECT=true
            shift
            ;;
		-b)
            BUILD_BOOTLOADER=true
            shift
            ;;
        -r)
            BUILD_ROOTFS=true
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
if [[ -z "$BASE_BSP" || -z "$TARGET_BSP" ]]; then
    echo "Error: --base-bsp and --target-bsp must be provided."
    exit 1
fi

# Check if the image exists
if [[ "$REBUILD_IMAGE" == true ]] || ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "Building Docker image..."
    docker build -t "$IMAGE_NAME" - <<EOF
FROM ubuntu:22.04
RUN apt-get update
RUN apt-get install -y apt-utils wget tar sudo bash libxml2-utils cpio binutils \
    openssh-client dosfstools util-linux device-tree-compiler python3 \
    python3-pip bc bzip2 xz-utils kmod qemu-user-static \
    pv zip unzip git curl libssl-dev rsync jq
RUN apt-get clean
RUN pip3 install --no-cache-dir pyyaml
RUN ln -s $(which python3) /usr/bin/python
WORKDIR /workspace
EOF
else
    echo "Using existing Docker image: $IMAGE_NAME"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_BSP_VER="$(basename $BASE_BSP)"
TARGET_BSP_VER="$(basename $TARGET_BSP)"

# Function to ensure BSP folder contains Linux_for_Tegra
ensure_linux_for_tegra() {
    local SRC_PATH="$1"
	local SRC_DIR=$(dirname "$1")
	local TMP_DIR="$SRC_DIR/Linux_for_Tegra"
    if [[ ! -d "$SRC_PATH/Linux_for_Tegra" ]]; then
        echo "Rearranging $SRC_PATH to include Linux_for_Tegra..."
        mv $SRC_PATH $TMP_DIR
        mkdir -p $SRC_PATH
        mv $TMP_DIR $SRC_PATH/
    fi
}

# Ensure BSP directories contain Linux_for_Tegra
ensure_linux_for_tegra "$TARGET_BSP"
if [[ "$BASE_BSP" != "$TARGET_BSP" ]]; then
	ensure_linux_for_tegra "$BASE_BSP"
fi

if [[ "$INSPECT" == true ]]; then
    echo "Entering inspection mode..."
    echo "docker run --rm -it --privileged \
        --device /dev/loop-control \
        --device /dev/loop0:/dev/loop0 \
        --device /dev/loop1:/dev/loop1 \
        -e SSH_AUTH_SOCK="$SSH_AUTH_SOCK" \
		-v /tmp:/tmp \
        -v "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK" \
        -v "$BASE_BSP:/workspace/base_bsp/$BASE_BSP_VER" \
        -v "$TARGET_BSP:/workspace/target_bsp/$TARGET_BSP_VER" \
        $(if [[ -n "$PARTITION_XML" ]]; then echo "-v $(dirname "$PARTITION_XML"):/workspace/xml"; fi) \
        -v "$SCRIPT_DIR:/workspace/script" \
        "$IMAGE_NAME" \
        bash"
    docker run --rm -it --privileged \
        --device /dev/loop-control \
        --device /dev/loop0:/dev/loop0 \
        --device /dev/loop1:/dev/loop1 \
        -e SSH_AUTH_SOCK="$SSH_AUTH_SOCK" \
		-v /tmp:/tmp \
        -v "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK" \
        -v "$BASE_BSP:/workspace/base_bsp/$BASE_BSP_VER" \
        -v "$TARGET_BSP:/workspace/target_bsp/$TARGET_BSP_VER" \
        $(if [[ -n "$PARTITION_XML" ]]; then echo "-v $(dirname "$PARTITION_XML"):/workspace/xml"; fi) \
        -v "$SCRIPT_DIR:/workspace/script" \
        "$IMAGE_NAME" \
        bash
    exit 0
fi

docker run --rm -it --privileged \
    --device /dev/loop-control \
    --device /dev/loop0:/dev/loop0 \
    --device /dev/loop1:/dev/loop1 \
	-e SSH_AUTH_SOCK="$SSH_AUTH_SOCK" \
	-v /tmp:/tmp \
	-v "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK" \
    -v "$BASE_BSP:/workspace/base_bsp/$BASE_BSP_VER" \
    -v "$TARGET_BSP:/workspace/target_bsp/$TARGET_BSP_VER" \
    $(if [[ -n "$PARTITION_XML" ]]; then echo "-v $(dirname "$PARTITION_XML"):/workspace/xml"; fi) \
    -v "$SCRIPT_DIR:/workspace/script" \
    "$IMAGE_NAME" \
    bash -c "
    cd /workspace/script && \
    sudo ./create_ota_payload.sh \
        --base-bsp /workspace/base_bsp/"$BASE_BSP_VER" \
        --target-bsp /workspace/target_bsp/"$TARGET_BSP_VER" \
        $(if [[ -n "$PARTITION_XML" ]]; then echo "--partition-xml /workspace/xml/$(basename "$PARTITION_XML")"; fi) \
        $(if $FORCE_PARTITION_CHANGE; then echo '--force-partition-change'; fi) \
        $(if $BUILD_BOOTLOADER; then echo '-b'; fi) \
        $(if $BUILD_ROOTFS; then echo '-r'; fi) \
		$(if [[ -n "$DEPLOY_IP" ]]; then echo "--deploy $DEPLOY_IP"; fi) \
        $(if $SKIP_BUILD; then echo '--skip-build'; fi)
    "

echo "OTA payload generation completed."

