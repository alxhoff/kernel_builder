#!/bin/bash

set -e

# Display help message
show_help() {
    echo "Usage: $0 --otapayload <path> --kernel-version <version> --repo-version <version> --target-bsp <version>"
    echo
    echo "Options:"
    echo "  --otapayload <path>    Path to the OTA payload package."
    echo "  --kernel-version <ver> Kernel version."
    echo "  --repo-version <ver>   Repository version."
    echo "  --target-bsp <ver>     Target BSP version (Only 5.1.3 supported currently)."
    echo "  --help                 Show this help message and exit."
    echo
    exit 0
}

# Parse command-line arguments
OTA_PAYLOAD=""
KERNEL_VERSION=""
REPO_VERSION=""
TARGET_BSP=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --otapayload)
            OTA_PAYLOAD="$2"
            shift 2
            ;;
        --kernel-version)
            KERNEL_VERSION="$2"
            shift 2
            ;;
        --repo-version)
            REPO_VERSION="$2"
            shift 2
            ;;
        --target-bsp)
            TARGET_BSP="$2"
            shift 2
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Ensure all required parameters are provided
if [[ -z "$OTA_PAYLOAD" || -z "$KERNEL_VERSION" || -z "$REPO_VERSION" || -z "$TARGET_BSP" ]]; then
    echo "Error: All parameters must be provided."
    show_help
fi

# Validate supported BSP versions
if [[ "$TARGET_BSP" != "5.1.3" ]]; then
    echo "Error: Unsupported target BSP version. Currently, only 5.1.3 is supported."
    exit 1
fi

# Set OTA tools download URL
OTA_TOOLS_URL="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/release/ota_tools_R35.5.0_aarch64.tbz2"

# Remove any existing temp directory from previous runs
rm -rf /tmp/ota_tools

# Create Debian package structure
PKG_NAME="cartken-full-system-ota-kernel-release-${REPO_VERSION}-${KERNEL_VERSION}"
PKG_DIR="/tmp/${PKG_NAME}"
DEBIAN_DIR="$PKG_DIR/DEBIAN"
INSTALL_DIR="$PKG_DIR/usr/local/cartken/ota"
OTA_INSTALL_DIR="$PKG_DIR/ota"

mkdir -p "$DEBIAN_DIR"
mkdir -p "$OTA_INSTALL_DIR"

# Create control file
cat << EOF > "$DEBIAN_DIR/control"
Package: $PKG_NAME
Version: 1.0.0
Architecture: arm64
Maintainer: Alex Hoffman <alxhoff@cartken.com>
Description: Full system OTA update package for release $REPO_VERSION and with kernel version $KERNEL_VERSION
EOF

# Download and store OTA tools tarball without extracting
wget -O "$OTA_INSTALL_DIR/ota_tools.tbz2" "$OTA_TOOLS_URL"

# Move OTA payload tarball into package without extracting
install -m 644 "$OTA_PAYLOAD" "$OTA_INSTALL_DIR/ota_payload_package.tar.gz"

# Create a post-install script to extract and execute OTA update on the target machine
cat << 'EOF' > "$DEBIAN_DIR/postinst"
#!/bin/bash
set -e

# Extract OTA tools
mkdir -p /tmp/ota_tools
tar -xjf /ota/ota_tools.tbz2 -C /tmp/ota_tools && rm /ota/ota_tools.tbz2

# Set working directory
export WORKDIR="/tmp/ota_tools"

# Execute the OTA update
cd "${WORKDIR}/Linux_for_Tegra/tools/ota_tools/version_upgrade"
sudo ./nv_ota_start.sh /ota/ota_payload_package.tar.gz
EOF

# Make the post-install script executable
chmod 755 "$DEBIAN_DIR/postinst"

# Build the Debian package
dpkg-deb --build "$PKG_DIR"

# Move the package to the current directory
mv "/tmp/${PKG_NAME}.deb" "./${PKG_NAME}.deb"

echo "Debian package created: ${PKG_NAME}.deb"

# Cleanup temporary package directory
rm -rf "$PKG_DIR"

