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
    echo "  --target-bsp <ver>     Target BSP version"
    echo "  --base-bsp <ver>       Base BSP version."
    echo "  --help                 Show this help message and exit."
    echo
    exit 0
}

# Parse command-line arguments
OTA_PAYLOAD=""
KERNEL_VERSION=""
REPO_VERSION=""
TARGET_BSP=""
BASE_BSP=""
EXTLINUX_CONF=""
PACKAGE_SUFFIX=""

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
        --base-bsp)
            BASE_BSP="$2"
            shift 2
            ;;
        --target-bsp)
            TARGET_BSP="$2"
            shift 2
            ;;
		--extlinux-conf)
            EXTLINUX_CONF="$2"
            shift 2
            ;;
		--package-suffix)
            PACKAGE_SUFFIX="$2"
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

if [[ -z "$OTA_PAYLOAD" || -z "$KERNEL_VERSION" || -z "$REPO_VERSION" || -z "$TARGET_BSP" ]]; then
    echo "Error: All parameters must be provided."
    show_help
fi

if [[ -n "$EXTLINUX_CONF" && ! -f "$EXTLINUX_CONF" ]]; then
    echo "Error: Specified extlinux.conf file does not exist: $EXTLINUX_CONF"
    exit 1
fi

case "$TARGET_BSP" in
    5.1.2|5.1.3|5.1.4|5.1.5|6.1|6.2) ;;
    *)
        echo "Error: Unsupported target BSP version. Supported versions are 5.1.2, 5.1.3, 5.1.4, 5.1.5, 6.1, and 6.2."
        exit 1
        ;;
esac

case "$TARGET_BSP" in
    "6.2")
        OTA_TOOLS_URL="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/release/ota_tools_r36.4.3_aarch64.tbz2"
        ;;
    "6.1")
        OTA_TOOLS_URL="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.0/release/ota_tools_r36.4.0_aarch64.tbz2"
        ;;
    "5.1.5")
        OTA_TOOLS_URL="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.1/release/ota_tools_R35.6.1_aarch64.tbz2"
        ;;
    "5.1.4")
        OTA_TOOLS_URL="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.0/release/ota_tools_R35.6.0_aarch64.tbz2"
        ;;
    "5.1.3")
        OTA_TOOLS_URL="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/release/ota_tools_R35.5.0_aarch64.tbz2"
        ;;
    "5.1.2")
        OTA_TOOLS_URL="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/release/ota_tools_r35.4.1_aarch64.tbz2"
        ;;
    *)
        echo "Error: Unsupported target BSP version. Supported: 5.1.2, 5.1.3, 5.1.4, 5.1.5, 6.1, 6.2"
        exit 1
        ;;
esac

rm -rf /tmp/ota_tools

PKG_NAME="cartken-full-system-ota-from-${BASE_BSP}-to-${TARGET_BSP}-release-${REPO_VERSION}-kernel-${KERNEL_VERSION}"
if [[ -n "$PACKAGE_SUFFIX" ]]; then
    PKG_NAME="${PKG_NAME}-${PACKAGE_SUFFIX}"
fi
#PKG_DIR="/tmp/${PKG_NAME}"
PKG_DIR="./${PKG_NAME}"
DEBIAN_DIR="$PKG_DIR/DEBIAN"
INSTALL_DIR="$PKG_DIR/usr/local/cartken/ota"
OTA_INSTALL_DIR="$PKG_DIR/ota"

mkdir -p "$DEBIAN_DIR"
mkdir -p "$OTA_INSTALL_DIR"

cat << EOF > "$DEBIAN_DIR/control"
Package: $PKG_NAME
Version: 1.0.0
Architecture: arm64
Maintainer: Alex Hoffman <alxhoff@cartken.com>
Description: Full system OTA update package for release $REPO_VERSION and with kernel version $KERNEL_VERSION
EOF

wget -O "$OTA_INSTALL_DIR/ota_tools.tbz2" "$OTA_TOOLS_URL"

install -m 644 "$OTA_PAYLOAD" "$OTA_INSTALL_DIR/ota_payload_package.tar.gz"

# if [[ -n "$EXTLINUX_CONF" ]]; then
#     cp "$EXTLINUX_CONF" "$OTA_INSTALL_DIR/extlinux.conf"
#     EXTLINUX_CONF="$OTA_INSTALL_DIR/extlinux.conf"
#
#     echo "Updating extlinux.conf to use DTB: $DTB_PATH"
#
#     # Replace any existing FDT entry with the new DTB path
#     sudo sed -i "s|^FDT .*$|FDT $DTB_PATH|" "$EXTLINUX_CONF"
#
#     # If no FDT entry exists, add it under LABEL entry
#     if ! grep -q "^FDT " "$EXTLINUX_CONF"; then
#         sudo sed -i "/^LABEL /a FDT $DTB_PATH" "$EXTLINUX_CONF"
#     fi
#
#     # Define the required APPEND line
#     REQUIRED_APPEND="    APPEND \${cbootargs} root=/dev/mmcblk0p1 rw rootwait rootfstype=ext4 mminit_loglevel=4 console=ttyTCU0,115200 console=tty0 firmware_class.path=/etc/firmware fbcon=map:0 net.ifnames=0"
#
#     # Ensure we only modify the APPEND line **inside the LABEL primary block**
#     awk -v append="$REQUIRED_APPEND" '
#     BEGIN { inside_label=0 }
#     /^LABEL primary$/ { inside_label=1 }
#     /^LABEL / && !/^LABEL primary$/ { inside_label=0 }
#     inside_label && /^ *APPEND / { $0=append }
#     { print }
#     ' "$EXTLINUX_CONF" > "$EXTLINUX_CONF.tmp" && mv "$EXTLINUX_CONF.tmp" "$EXTLINUX_CONF"
#
# fi

cat << 'EOF' > "$DEBIAN_DIR/postinst"
#!/bin/bash
set -e

# Extract OTA tools
mkdir -p /tmp/ota_tools
tar -xjf /ota/ota_tools.tbz2 -C /tmp/ota_tools && rm /ota/ota_tools.tbz2

# Replace /boot/extlinux/extlinux.conf if provided
if [[ -f /ota/extlinux.conf ]]; then
    echo "Replacing /boot/extlinux/extlinux.conf with provided version..."
    cp /ota/extlinux.conf /boot/extlinux/extlinux.conf
fi

# Set working directory
export WORKDIR="/tmp/ota_tools"

# Execute the OTA update
cd "${WORKDIR}/Linux_for_Tegra/tools/ota_tools/version_upgrade"
sudo ./nv_ota_start.sh /ota/ota_payload_package.tar.gz
cartken-toggle-watchdog off || true
EOF

chmod 755 "$DEBIAN_DIR/postinst"

dpkg-deb --build "$PKG_DIR"

#mv "/tmp/${PKG_NAME}.deb" "./${PKG_NAME}.deb"

echo "Debian package created: ${PKG_NAME}.deb"

rm -rf "$PKG_DIR"

