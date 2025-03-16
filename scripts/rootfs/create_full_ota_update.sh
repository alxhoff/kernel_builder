#!/bin/bash

# Help message function
usage() {
    echo "Usage: $0 --access-token <token> --tag <tag> --base-jetpack <base_version> --target-jetpack <target_version>"
    echo "\nOptions:"
    echo "  --access-token   A GitLab access token required to fetch the repository release."
    echo "  --tag            The tag version for the release."
    echo "  --base-jetpack   The current Jetson BSP version you have."
    echo "  --target-jetpack The Jetson BSP version you are updating to (can be the same as base)."
    echo "\nIf the base and target BSP versions are the same, the second call to setup_tegra_package_docker.sh is skipped."
    exit 1
}

# Parse arguments
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

# Run setup_tegra_package_docker.sh with base Jetpack version
echo "Running setup_tegra_package_docker.sh with base Jetpack version: $BASE_JETPACK"
sudo ./setup_tegra_package_docker.sh --access-token "$ACCESS_TOKEN" --tag "$TAG" --jetpack "$BASE_JETPACK"

# Remove all .tbz2 files in the working directory
echo "Removing all .tbz2 files from working directory"
rm -f *.tbz2

# Run setup_tegra_package_docker.sh with target Jetpack version if different from base
if [[ "$BASE_JETPACK" != "$TARGET_JETPACK" ]]; then
    echo "Running setup_tegra_package_docker.sh with target Jetpack version: $TARGET_JETPACK"
    sudo ./setup_tegra_package_docker.sh --access-token "$ACCESS_TOKEN" --tag "$TAG" --jetpack "$TARGET_JETPACK"
else
    echo "Base and target Jetpack versions are the same, skipping second setup_tegra_package_docker.sh call."
fi

# Move into ota_update directory
cd ota_update || { echo "Failed to enter ota_update directory"; exit 1; }

# Run create_ota_payload_docker.sh with given base and target BSP versions
echo "Running create_ota_payload_docker.sh with base BSP: $BASE_JETPACK and target BSP: $TARGET_JETPACK"
sudo ./create_ota_payload_docker.sh --base-bsp "../$BASE_JETPACK" --target-bsp "../$TARGET_JETPACK"

echo "Full OTA update process completed successfully."

