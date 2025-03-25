#!/bin/bash

set -e

TEGRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR=$(mktemp -d)
TOOLCHAIN_DIR="$TMP_DIR/toolchain/bin"
KERNEL_SRC_ROOT="$TMP_DIR/kernel_src"
CROSS_COMPILE="$TOOLCHAIN_DIR/aarch64-buildroot-linux-gnu-"
MAKE_ARGS="ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE -j$(nproc)"
MENUCONFIG=false
LOCALVERSION=""
PATCH="5.1.3"
PATCH_SOURCE=false
CREATE_DEB=true

# JetPack -> L4T version map
declare -A JETPACK_L4T_MAP=(
    [5.1.3]=35.5.0
    [5.1.2]=35.4.1
    [6.0DP]=36.2
    [6.2]=36.4.3
)

# Kernel source URLs
declare -A KERNEL_URLS=(
    [5.1.3]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/sources/public_sources.tbz2"
    [5.1.2]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/sources/public_sources.tbz2"
    [6.0DP]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v2.0/sources/public_sources.tbz2"
    [6.2]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/sources/public_sources.tbz2"
)

show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --patch VERSION       Specify JetPack version (default: $PATCH)"
    echo "  --menuconfig          Run menuconfig before build"
    echo "  --localversion STR    Append local version string"
    echo "  --no-deb              Skip .deb package creation"
    echo "  -h, --help            Show this help"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --patch)
            PATCH="$2"; PATCH_SOURCE=true; shift 2;;
        --menuconfig)
            MENUCONFIG=true; shift;;
        --localversion)
            LOCALVERSION="$2"; shift 2;;
        --no-deb)
            CREATE_DEB=false; shift;;
        -h|--help)
            show_help;;
        *) echo "Unknown option: $1"; show_help;;
    esac
done

if [[ -z "${JETPACK_L4T_MAP[$PATCH]}" ]]; then
    echo "Unsupported JetPack version"; exit 1
fi

if [ ! -d "$TOOLCHAIN_DIR" ]; then
    echo "Cloning toolchain..."
    git clone --depth=1 https://github.com/alxhoff/jetson-linux-toolchain "$TMP_DIR/toolchain"
fi

KERNEL_TARBALL="$(basename ${KERNEL_URLS[$PATCH]})"
echo "Downloading kernel source..."
wget -c "${KERNEL_URLS[$PATCH]}" -O "$TMP_DIR/$KERNEL_TARBALL"
echo "Extracting public sources..."
tar -xjf "$TMP_DIR/$KERNEL_TARBALL" -C "$TMP_DIR"
mkdir -p "$KERNEL_SRC_ROOT"
tar -xjf "$TMP_DIR/Linux_for_Tegra/source/public/kernel_src.tbz2" -C "$KERNEL_SRC_ROOT"

# Rename kernel directory to 'kernel'
KERNEL_PARENT="$KERNEL_SRC_ROOT/kernel"
mkdir -p "$KERNEL_PARENT"
KERNEL_ORIG_DIR=$(find "$KERNEL_PARENT" -mindepth 1 -maxdepth 1 -type d -name "kernel*" | head -n 1)
if [[ -n "$KERNEL_ORIG_DIR" && "$KERNEL_ORIG_DIR" != "$KERNEL_PARENT/kernel" ]]; then
    mv "$KERNEL_ORIG_DIR" "$KERNEL_PARENT/kernel"
fi

# Apply patches if enabled
GIT_PATCH_URL="https://api.github.com/repos/alxhoff/kernel_builder/contents/patches/$PATCH"
if [ "$PATCH_SOURCE" = true ]; then
    PATCH_DIR="$TMP_DIR/kernel_patches"
    mkdir -p "$PATCH_DIR"
    echo "Fetching patch list for $PATCH..."
    PATCH_LIST=$(curl -s "$GIT_PATCH_URL")
    if ! echo "$PATCH_LIST" | jq empty 2>/dev/null; then
        echo "Invalid JSON from patch source"; exit 1
    fi
    echo "$PATCH_LIST" | jq -r '.[] | select(.name != ".gitkeep" and .name != ".gitignore") | .download_url' | grep -v '^$' | while read -r FILE_URL; do
        [ -z "$FILE_URL" ] && continue
        FILE_NAME=$(basename "$FILE_URL")
        PATCH_FILE="$PATCH_DIR/$FILE_NAME"
        echo "Downloading patch $FILE_NAME..."
        wget -q -O "$PATCH_FILE" "$FILE_URL"
        if [[ -f "$PATCH_FILE" ]]; then
            echo "Applying patch $FILE_NAME..."
            patch -p1 -d "$KERNEL_SRC_ROOT" --batch --forward < "$PATCH_FILE" || echo "Warning: Some hunks failed!"
        fi
    done
fi

KERNEL_SRC="$KERNEL_SRC_ROOT/kernel/kernel"
cd "$KERNEL_SRC"
make $MAKE_ARGS mrproper
wget -O arch/arm64/configs/defconfig "https://raw.githubusercontent.com/alxhoff/kernel_builder/refs/heads/master/configs/$PATCH/defconfig"

if $MENUCONFIG; then
    make $MAKE_ARGS menuconfig
fi

KERNEL_VERSION_SUFFIX="${LOCALVERSION:+$LOCALVERSION}"

# Setup packaging dir
KERNEL_VERSION=""
PKG_NAME=""
DEB_TMP_DIR=$(mktemp -d)

make $MAKE_ARGS LOCALVERSION="$KERNEL_VERSION_SUFFIX" defconfig
make $MAKE_ARGS LOCALVERSION="$KERNEL_VERSION_SUFFIX"

make $MAKE_ARGS LOCALVERSION="$KERNEL_VERSION_SUFFIX" modules_install INSTALL_MOD_PATH="$DEB_TMP_DIR/root"
KERNEL_VERSION=$(basename $(find "$DEB_TMP_DIR/root/lib/modules/" -mindepth 1 -maxdepth 1 -type d | head -n1))
PKG_NAME="linux-custom-${KERNEL_VERSION}"
PKG_DIR="$DEB_TMP_DIR/$PKG_NAME"
mkdir -p "$PKG_DIR/DEBIAN" "$PKG_DIR/boot/dtb" "$PKG_DIR/lib/modules"
mv "$DEB_TMP_DIR/root/lib/modules/$KERNEL_VERSION" "$PKG_DIR/lib/modules/"

cp "$KERNEL_SRC/arch/arm64/boot/Image" "$PKG_DIR/boot/"
cp "$KERNEL_SRC/arch/arm64/boot/dts/nvidia/tegra234-p3701-0000-p3737-0000.dtb" "$PKG_DIR/boot/dtb/"

cat <<EOF > "$PKG_DIR/DEBIAN/control"
Package: $PKG_NAME
Version: $KERNEL_VERSION
Architecture: arm64
Maintainer: Kernel Builder <noreply@example.com>
Description: Custom Jetson Kernel $KERNEL_VERSION
Depends: initramfs-tools
Section: kernel
Priority: optional
EOF

cat <<EOF > "$PKG_DIR/DEBIAN/postinst"
#!/bin/bash
set -e

cp /boot/Image /boot/Image.previous
cp /boot/Image /boot/Image
cp /boot/dtb/tegra234*.dtb /boot/dtb/

EXTLINUX_CONF="/boot/extlinux/extlinux.conf"
sed -i "s|^LINUX .*|LINUX /boot/Image|" "\$EXTLINUX_CONF"
sed -i "s|^INITRD .*|INITRD /boot/initrd.img-$KERNEL_VERSION|" "\$EXTLINUX_CONF"
sed -i "s|^FDT .*|FDT /boot/dtb/tegra234-p3701-0000-p3737-0000.dtb|" "\$EXTLINUX_CONF"

depmod $KERNEL_VERSION
update-initramfs -c -k $KERNEL_VERSION
EOF
chmod 0755 "$PKG_DIR/DEBIAN/postinst"

# Build third-party drivers
THIRD_PARTY_DRIVERS="rtl8192eu rtl88x2bu"
DRIVER_SCRIPTS_DIR="$TEGRA_DIR/../rootfs"
DRIVER_OUTPUT_DIR="$PKG_DIR/lib/modules/$KERNEL_VERSION/kernel/drivers/net/wireless"
mkdir -p "$DRIVER_OUTPUT_DIR"
echo "Building third party drivers..."
for DRIVER in $THIRD_PARTY_DRIVERS; do
    echo "Building and installing $DRIVER"
    DRIVER_SCRIPT="$DRIVER_SCRIPTS_DIR/${DRIVER}.sh"
    if [[ -x "$DRIVER_SCRIPT" ]]; then
        echo "$DRIVER_SCRIPT --kernel-src $KERNEL_SRC_ROOT --toolchain $CROSS_COMPILE --localversion $KERNEL_VERSION_SUFFIX"
        "$DRIVER_SCRIPT" --kernel-src "$KERNEL_SRC_ROOT" --toolchain "$CROSS_COMPILE" --localversion "$KERNEL_VERSION_SUFFIX"
    else
        echo "Error: Driver script $DRIVER_SCRIPT not found or not executable"
        exit 1
    fi

done

# Copy all built .ko files once
for KO_FILE in "$DRIVER_SCRIPTS_DIR"/*.ko; do
    if [[ -f "$KO_FILE" ]]; then
        echo "Copying $(basename "$KO_FILE") into module tree"
        cp "$KO_FILE" "$DRIVER_OUTPUT_DIR/"
    fi
done

depmod -b "$PKG_DIR" "$KERNEL_VERSION"
    depmod -b "$PKG_DIR" "$KERNEL_VERSION"
done

OUTPUT_DEB="$TEGRA_DIR/$PKG_NAME.deb"
dpkg-deb --build "$PKG_DIR" "$OUTPUT_DEB"
echo "✅ Debian package created at: $OUTPUT_DEB"

