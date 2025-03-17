#!/bin/bash

# Ensure the script is run with sudo
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

# Help message function
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
run_command ./setup_tegra_package_docker.sh --access-token "$ACCESS_TOKEN" --tag "$TAG" --jetpack "$TARGET_JETPACK"

echo "Removing all .tbz2 files from working directory"
run_command rm -f *.tbz2

if [[ "$BASE_JETPACK" != "$TARGET_JETPACK" ]]; then
	echo "Running setup_tegra_package_docker.sh with base Jetpack version: $BASE_JETPACK"
	run_command ./setup_tegra_package_docker.sh --access-token "$ACCESS_TOKEN" --tag "$TAG" --jetpack "$BASE_JETPACK" --skip-kernel-build --skip-chroot-build
else
    echo "Base and target Jetpack versions are the same, skipping second setup_tegra_package_docker.sh call."
fi

echo "Moving into ota_update directory"
run_command cd ota_update || { echo "Failed to enter ota_update directory"; exit 1; }

echo "Running create_ota_payload_docker.sh with base BSP: $BASE_JETPACK and target BSP: $TARGET_JETPACK"
run_command ./create_ota_payload_docker.sh --base-bsp "../$BASE_JETPACK" --target-bsp "../$TARGET_JETPACK"

KERNEL_VERSION=$(strings "../$TARGET_JETPACK/Linux_for_Tegra/kernel/Image" | grep -oP "Linux version \K[0-9.-]+-[^ ]+")
echo "Extracted kernel version: $KERNEL_VERSION"

echo "Running create_debian.sh with extracted kernel version"
run_command ./create_debian.sh \
    --otapayload "../$TARGET_JETPACK/Linux_for_Tegra/bootloader/jetson-agx-orin-devkit/ota_payload_package.tar.gz" \
    --kernel-version "$KERNEL_VERSION" \
    --repo-version "$TAG" \
    --target-bsp "$TARGET_JETPACK"

echo "Full OTA update process completed successfully."

