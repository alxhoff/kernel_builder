#!/bin/bash

set -e

# Default values
DRY_RUN=false
DEPLOY_IP=""
BASE_BSP=""
TARGET_BSP=""

declare -A BSP_VERSION_MAP=(
    [5.1.2]="R35-4"
    [5.1.3]="R35-5"
    [6.0DP]="R36-2"
    [6.2]="R36-2"
)

declare -A OTA_TOOL_URLS=(
    [5.1.2]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/release/ota_tools_r35.4.1_aarch64.tbz2"
    [5.1.3]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/release/ota_tools_R35.5.0_aarch64.tbz2"
    [6.0DP]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v3.0/release/ota_tools_R36.3.0_aarch64.tbz2"
    [6.2]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/release/ota_tools_r36.4.3_aarch64.tbz2"
)

# Function to show help
show_help() {
    echo "Usage: $0 --base-bsp <path> --target-bsp <path> [--deploy <device-ip>] [--dry-run]"
    echo "Options:"
    echo "  --base-bsp PATH     Path to the BASE BSP source (e.g., 5.1.2)"
    echo "  --target-bsp PATH   Path to the TARGET BSP source (e.g., 5.1.3)"
    echo "  --deploy IP         Deploy the generated OTA update to the given device IP (e.g., 192.168.1.91)"
    echo "  --dry-run           Show commands that would be executed without running them"
    exit 0
}

# Function to execute or simulate commands
run_cmd() {
    if $DRY_RUN; then
        echo "[DRY-RUN] $1"
    else
        eval "$1"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-bsp)
            BASE_BSP=$(realpath "$2")/Linux_for_Tegra
            shift 2
            ;;
        --target-bsp)
            TARGET_BSP=$(realpath "$2")/Linux_for_Tegra
            shift 2
            ;;
        --deploy)
            DEPLOY_IP="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
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

# Ensure the script is run with sudo (after help is shown)
if [[ "$EUID" -ne 0 ]]; then
    echo "Error: This script must be run with sudo."
    exit 1
fi

# Validate required parameters
if [[ -z "$BASE_BSP" || -z "$TARGET_BSP" ]]; then
    echo "Error: Both --base-bsp and --target-bsp must be provided."
    exit 1
fi

# Extract version numbers
BASE_VERSION=$(basename "$(dirname "$BASE_BSP")")
TARGET_VERSION=$(basename "$(dirname "$TARGET_BSP")")

# Get correct BSP version for BASE_BSP
BASE_BSP_VERSION="${BSP_VERSION_MAP[$BASE_VERSION]}"
if [[ -z "$BASE_BSP_VERSION" ]]; then
    echo "Error: Unsupported BASE_BSP version ($BASE_VERSION)."
    exit 1
fi

# Get correct OTA tool URL for TARGET_BSP
OTA_TOOL_URL="${OTA_TOOL_URLS[$TARGET_VERSION]}"
OTA_TOOL_FILE="$(basename "$OTA_TOOL_URL")"

# Download OTA tools if missing
if [[ ! -f "$OTA_TOOL_FILE" ]]; then
    echo "Downloading OTA tools for target BSP $TARGET_VERSION..."
    run_cmd "wget -O \"$OTA_TOOL_FILE\" \"$OTA_TOOL_URL\""
else
    echo "OTA tools already downloaded."
fi

# Extract OTA tools
echo "Extracting OTA tools into $TARGET_BSP..."
run_cmd "cd $(dirname "$TARGET_BSP")"
run_cmd "sudo tar xpf \"$OTA_TOOL_FILE\""

# Generate OTA payload
echo "Generating OTA update payload..."
run_cmd "cd \"$TARGET_BSP\""
run_cmd "sudo -E ./tools/ota_tools/version_upgrade/l4t_generate_ota_package.sh jetson-agx-orin-devkit $BASE_BSP_VERSION"

# Find the generated payload
PAYLOAD_PATH="$TARGET_BSP/bootloader/jetson-agx-orin-devkit/ota_payload_package.tar.gz"
if [[ ! -f "$PAYLOAD_PATH" && "$DRY_RUN" == false ]]; then
    echo "Error: Failed to generate OTA payload!"
    exit 1
fi

echo "OTA payload generated successfully: $PAYLOAD_PATH"

# Deploy OTA update if --deploy is provided
if [[ -n "$DEPLOY_IP" ]]; then
    echo "Deploying OTA update to Jetson device at $DEPLOY_IP..."

    run_cmd "scp \"$OTA_TOOL_FILE\" root@$DEPLOY_IP:/home/root/"
    run_cmd "scp \"$PAYLOAD_PATH\" root@$DEPLOY_IP:/home/root/"

    run_cmd "ssh root@$DEPLOY_IP 'mkdir -p /home/root/ota_update && tar -xjf \"/home/root/$OTA_TOOL_FILE\" -C /home/root/ota_update'"
    run_cmd "ssh root@$DEPLOY_IP 'sudo mkdir -p /ota && sudo mv /home/root/ota_payload_package.tar.gz /ota/'"

    echo "Executing OTA update..."
    run_cmd "ssh root@$DEPLOY_IP 'cd /home/root/ota_update/Linux_for_Tegra/tools/ota_tools/version_upgrade && sudo ./nv_ota_start.sh /ota/ota_payload_package.tar.gz'"

    echo "Deployment completed!"
fi

echo "Script execution finished."

