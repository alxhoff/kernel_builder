#!/bin/bash
set -e

# --- Default Configuration ---
# These can be overridden with command-line arguments.
SOC_TYPE="orin"
DEPLOY_TAG="latest"
UBUNTU_VERSION="20.04"
REGISTRY="registry.gitlab.com"
REPO="cartken/repo"
UPDATE_MODE=false

# --- Help Message Function ---
print_help() {
  cat << EOF
Downloads a specific Docker image from the Cartken GitLab registry and saves it as a portable .tar archive.

This script automates the process of logging in, finding the correct image name based on SOC type, pulling the image, and saving it for offline use or transfer.

USAGE:
  ./get_docker.sh --username <your_gitlab_username> --access-token <your_gitlab_pat> [OPTIONS]

REQUIRED ARGUMENTS:
  --username      Your GitLab username.
  --access-token  Your GitLab Personal Access Token (PAT) with 'read_registry' scope.

OPTIONS:
  --soc           The target System-on-a-Chip (SOC) type.
                  Options: "xavier", "turing", "orin".
                  (Default: "${SOC_TYPE}")

  --tag           The version tag of the image to download.
                  (Default: "${DEPLOY_TAG}")

  --ubuntu        The Ubuntu version associated with the fallback image name.
                  (Default: "${UBUNTU_VERSION}")

  --update        Force a check for remote updates. If not set, the script will use a
                  local image if it exists, instead of re-pulling.

  --help          Display this help message and exit.

EXAMPLE:
  ./get_docker.sh \
    --username myuser \
    --access-token glpat-xxxxxxxxxxxx \
    --soc orin \
    --tag v7.1.0 \
    --update
EOF
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --username)
      USERNAME="$2"
      shift 2
      ;;
    --access-token)
      ACCESS_TOKEN="$2"
      shift 2
      ;;
    --soc)
      SOC_TYPE="$2"
      shift 2
      ;;
    --tag)
      DEPLOY_TAG="$2"
      shift 2
      ;;
    --ubuntu)
      UBUNTU_VERSION="$2"
      shift 2
      ;;
    --update)
      UPDATE_MODE=true
      shift 1
      ;;
    --help)
      print_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for more information."
      exit 1
      ;;
  esac
done

# --- Prerequisite Checks ---
if [[ -z "$USERNAME" || -z "$ACCESS_TOKEN" ]]; then
  echo "Error: --username and --access-token are required."
  echo "Use --help for more information."
  exit 1
fi

command -v docker >/dev/null 2>&1 || { echo >&2 "Error: 'docker' command not found. Please install Docker and ensure it's in your PATH. Aborting."; exit 1; }

# --- Main Script Logic ---

# Step 1: Log in to the GitLab Container Registry
echo "Attempting to log in to Docker registry: ${REGISTRY}..."
echo "${ACCESS_TOKEN}" | docker login "${REGISTRY}" --username "${USERNAME}" --password-stdin
if [ $? -ne 0 ]; then
    echo "Error: Docker login failed. Please check your username and access token, then try again."
    exit 1
fi
echo "Docker login successful."

# Step 2: Determine which image name to pull based on SOC type
IMAGE_NAME_NEW="${REPO}/jetson-release-${SOC_TYPE}"
FULL_IMAGE_NEW_FORMAT="${REGISTRY}/${IMAGE_NAME_NEW}:${DEPLOY_TAG}"

echo "Checking for image using new format: ${FULL_IMAGE_NEW_FORMAT}"

# Use 'docker manifest inspect' to check for image existence without pulling.
# Note: This may require enabling experimental features in your Docker client.
if docker manifest inspect "${FULL_IMAGE_NEW_FORMAT}" > /dev/null 2>&1; then
    echo "New image format found."
    IMAGE_TO_PROCESS="${FULL_IMAGE_NEW_FORMAT}"
else
    echo "New image format not found or 'docker manifest inspect' failed. Falling back to old format."
    IMAGE_NAME_OLD="${REPO}/ros-${SOC_TYPE}-${UBUNTU_VERSION}-release"
    IMAGE_TO_PROCESS="${REGISTRY}/${IMAGE_NAME_OLD}:${DEPLOY_TAG}"
fi

echo "Selected image to process: ${IMAGE_TO_PROCESS}"

# Step 3: Pull the Docker image (if necessary)
LOCAL_IMAGE_EXISTS=false
if docker image inspect "${IMAGE_TO_PROCESS}" > /dev/null 2>&1; then
  LOCAL_IMAGE_EXISTS=true
fi

if [[ "$LOCAL_IMAGE_EXISTS" = true && "$UPDATE_MODE" = false ]]; then
  echo "Image '${IMAGE_TO_PROCESS}' already exists locally. Skipping pull."
  echo "Use --update to force a check for remote updates."
else
  if [[ "$UPDATE_MODE" = true ]]; then
    echo "Update mode: Checking for remote updates for '${IMAGE_TO_PROCESS}'..."
  else
    echo "Image not found locally. Pulling from registry..."
  fi
  docker pull "${IMAGE_TO_PROCESS}"
  if [ $? -ne 0 ]; then
      echo "Error: Docker pull failed for '${IMAGE_TO_PROCESS}'. Aborting."
      exit 1
  fi
  echo "Docker image pull successful."
fi

# Step 4: Save the Docker image to a portable .tar archive
SAVE_FILE_NAME="${IMAGE_TO_PROCESS//[:\/]/_}.tar" # Sanitize image name for a valid filename
echo "Saving Docker image '${IMAGE_TO_PROCESS}' to file: ${SAVE_FILE_NAME}..."
docker save "${IMAGE_TO_PROCESS}" -o "${SAVE_FILE_NAME}"
if [ $? -ne 0 ]; then
    echo "Error: Docker save failed. Aborting."
    exit 1
fi
echo "Docker image successfully saved to: ${SAVE_FILE_NAME}"

# --- Final Instructions ---
echo -e "\n--- Process Complete ---"
echo "You can now move the file '${SAVE_FILE_NAME}' to another machine."
echo "To load the image on the destination machine, use the command:"
echo "  docker load -i \"${SAVE_FILE_NAME}\""

exit 0

