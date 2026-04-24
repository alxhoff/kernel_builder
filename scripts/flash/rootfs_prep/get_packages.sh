#!/bin/bash

set -e

# Default values
NAMESPACE="cartken"
REPO_NAME="repo"
PACKAGE_TAG="latest"
ACCESS_TOKEN=""

# Function to show help
show_help() {
    echo "Usage: $0 --access-token TOKEN [options]"
    echo "Options:"
    echo "  --access-token TOKEN   GitLab access token (required)"
    echo "  --tag TAG              Override the default package tag (default: latest)"
    echo "  -h, --help             Show this help message"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --access-token)
            ACCESS_TOKEN="$2"
            shift 2
            ;;
        --tag)
            PACKAGE_TAG="$2"
            shift 2
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

# Validate access token
if [[ -z "$ACCESS_TOKEN" ]]; then
    echo "Error: Access token is required. Use --access-token TOKEN"
    exit 1
fi

# Get Project ID
PROJECT_ID=$(curl --silent --header "PRIVATE-TOKEN: $ACCESS_TOKEN" \
    "https://gitlab.com/api/v4/projects/cartken%2Frepo" | jq -r '.id')

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]]; then
    echo "Error: Could not find project ID for '$NAMESPACE/$REPO_NAME'"
    exit 1
fi

echo "Project ID: $PROJECT_ID"

# Function to fetch a package by name
fetch_package() {
    PACKAGE_NAME="$1"
    OUTPUT_DIR="packages/$PACKAGE_NAME"
    mkdir -p "$OUTPUT_DIR"

    echo "Fetching package: $PACKAGE_NAME with tag: $PACKAGE_TAG"

    # Define the package zip file URL
    PACKAGE_URL="https://gitlab.com/api/v4/projects/$PROJECT_ID/packages/generic/$PACKAGE_NAME/$PACKAGE_TAG/$PACKAGE_NAME.zip"

    # Download the package zip file
    curl --location --header "PRIVATE-TOKEN: $ACCESS_TOKEN" \
        --output "$OUTPUT_DIR/$PACKAGE_NAME.zip" \
        --create-dirs "$PACKAGE_URL"

    echo "Downloaded: $PACKAGE_NAME.zip"

    # Unzip the package
    echo "Unzipping: $PACKAGE_NAME.zip"
    unzip -o "$OUTPUT_DIR/$PACKAGE_NAME.zip" -d "$OUTPUT_DIR"
    echo "Unzipped: $PACKAGE_NAME.zip"

}

# Fetch both required packages
fetch_package "cartken-wheels"
fetch_package "cartken-jetson-debians"

echo "All requested packages have been downloaded."

