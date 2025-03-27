#!/bin/bash

# Ensure the script is run with sudo
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

usage() {
    echo "Usage: $0 --access-token <token> --tag <tag> --base-jetpack <base_version> --target-jetpack <target_version> [--dry-run]"
    echo "\nOptions:"
    echo "  --access-token   A GitLab access token required to fetch the repository release."
    echo "  --tag            The tag version for the release."
    echo "  --base-jetpack   The current Jetson BSP version you have."
    echo "  --target-jetpack The Jetson BSP version you are updating to (can be the same as base)."
    echo "  --dry-run        Show the commands without executing them."
    echo "\nIf the base and target BSP versions are the same, the second call to setup_tegra_package_docker.sh is skipped."
    exit 1
}

DRY_RUN=false

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --access-token)
            ACCESS_TOKEN="$2"
            shift 2
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        --base-jetpack)
            BASE_JETPACK="$2"
            shift 2
            ;;
        --target-jetpack)
            TARGET_JETPACK="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            usage
            ;;
    esac
done

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OTA_DIR="$WORKDIR/ota_update"
BASE_BSP_ROOT="$WORKDIR/$BASE_JETPACK"
TARGET_BSP_ROOT="$WORKDIR/$TARGET_JETPACK"
L4T_DIR="$TARGET_BSP_ROOT/Linux_for_Tegra"

# Ensure required arguments are set
if [[ -z "$ACCESS_TOKEN" || -z "$TAG" || -z "$BASE_JETPACK" || -z "$TARGET_JETPACK" ]]; then
    usage
fi

run_command() {
    echo "$@"
    if [ "$DRY_RUN" = false ]; then
        eval "$@"
    fi
}

echo "Running setup_tegra_package_docker.sh with target Jetpack version: $TARGET_JETPACK"
run_command "$WORKDIR"/setup_tegra_package_docker.sh --access-token "$ACCESS_TOKEN" --tag "$TAG" --jetpack "$TARGET_JETPACK"

if [[ "$BASE_JETPACK" != "$TARGET_JETPACK" ]]; then
	echo "Removing all .tbz2 files from working directory"
	run_command rm -f "$WORKDIR"/*.tbz2

	echo "Running setup_tegra_package_docker.sh with base Jetpack version: $BASE_JETPACK"
	run_command "$WORKDIR"/setup_tegra_package_docker.sh --access-token "$ACCESS_TOKEN" --tag "$TAG" --jetpack "$BASE_JETPACK" --skip-kernel-build --skip-chroot-build
else
    echo "Base and target Jetpack versions are the same, skipping second setup_tegra_package_docker.sh call."
fi

echo "Running create_ota_payload_docker.sh with base BSP: $BASE_JETPACK and target BSP: $TARGET_JETPACK"
run_command "$OTA_DIR"/create_ota_payload_docker.sh --base-bsp "$BASE_BSP_ROOT" --target-bsp "$TARGET_BSP_ROOT"

KERNEL_VERSION=$(strings "$L4T_DIR/kernel/Image" | grep -oP "Linux version \K[0-9.-]+-[^ ]+")
echo "Extracted kernel version: $KERNEL_VERSION"

echo "Running create_debian.sh with extracted kernel version"
run_command "$OTA_DIR"/create_debian.sh \
    --otapayload "$L4T_DIR/bootloader/jetson-agx-orin-devkit/ota_payload_package.tar.gz" \
    --kernel-version "$KERNEL_VERSION" \
    --repo-version "$TAG" \
    --target-bsp "$TARGET_JETPACK" \
    --base-bsp "$BASE_JETPACK" \
    --extlinux-conf "$L4T_DIR/rootfs/boot/extlinux/extlinux.conf"

echo "Full OTA update process completed successfully."

