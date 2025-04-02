#!/bin/bash

set -e

TEGRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MENUCONFIG=false
LOCALVERSION=""
PATCH="5.1.3"
PATCH_SOURCE=false
CREATE_DEB=true
OUTPUT_DIR=""

# JetPack -> L4T version map
declare -A JETPACK_L4T_MAP=(
    [5.1.2]=35.4.1
    [5.1.3]=35.5.0
	[5.1.4]=35.6.0
	[5.1.5]=35.6.1
    [6.0DP]=36.2
    [6.2]=36.4.3
)

# Kernel source URLs
declare -A KERNEL_URLS=(
    [5.1.2]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/sources/public_sources.tbz2"
    [5.1.3]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/sources/public_sources.tbz2"
	[5.1.4]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.0/sources/public_sources.tbz2"
	[5.1.5]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.1/sources/public_sources.tbz2"
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
	echo "  --output-dir		  If specified then the building and output will be done here instead of in /tmp"
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
		--output-dir)
			OUTPUT_DIR="$(realpath "$2")"; shift 2;;
        -h|--help)
            show_help;;
        *) echo "Unknown option: $1"; show_help;;
    esac
done

if [[ "$LOCALVERSION" == *"_"* ]]; then
    echo "Error: LOCALVERSION must not contain underscores"
    exit 1
fi

if [[ -z "${JETPACK_L4T_MAP[$PATCH]}" ]]; then
    echo "Unsupported JetPack version"; exit 1
fi

if [[ -n "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
    TMP_DIR="$OUTPUT_DIR"
else
    TMP_DIR=$(mktemp -d)
fi

KERNEL_SRC_ROOT="$TMP_DIR/kernel_src"
TOOLCHAIN_ROOT_DIR="$TMP_DIR/toolchain"
TOOLCHAIN_DIR="$TOOLCHAIN_ROOT_DIR/bin"
CROSS_COMPILE="$TOOLCHAIN_DIR/aarch64-buildroot-linux-gnu-"
MAKE_ARGS="ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE -j$(nproc)"

if [ ! -d "$TOOLCHAIN_DIR" ]; then
    echo "Cloning toolchain..."
    git clone --depth=1 https://github.com/alxhoff/jetson-linux-toolchain "$TMP_DIR/toolchain"
fi

KERNEL_TARBALL="$(basename ${KERNEL_URLS[$PATCH]})"
KERNEL_TARBALL_PATH="$TMP_DIR/$KERNEL_TARBALL"

if [[ ! -d "$KERNEL_SRC_ROOT/kernel" ]]; then
    echo "Downloading kernel source..."
    wget -c "${KERNEL_URLS[$PATCH]}" -O "$KERNEL_TARBALL_PATH"
    echo "Extracting public sources..."
    tar -xjf "$KERNEL_TARBALL_PATH" -C "$TMP_DIR"
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
else
    echo "Kernel source already extracted, skipping."
fi


KERNEL_SRC="$KERNEL_SRC_ROOT/kernel/kernel"
cd "$KERNEL_SRC"
#make $MAKE_ARGS mrproper
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

cp "$KERNEL_SRC/arch/arm64/boot/Image" "$PKG_DIR/boot/Image-$KERNEL_VERSION"
cp "$KERNEL_SRC/arch/arm64/boot/dts/nvidia/tegra234-p3701-0000-p3737-0000.dtb" "$PKG_DIR/boot/dtb/tegra234-p3701-0000-p3737-0000-$KERNEL_VERSION.dtb"

cat <<EOF > "$PKG_DIR/DEBIAN/control"
Package: $PKG_NAME
Version: $KERNEL_VERSION
Architecture: arm64
Maintainer: Alex Hoffman <alxhoff@cartken.com>
Description: Custom Jetson Kernel $KERNEL_VERSION
Depends: initramfs-tools
Conflicts: nvidia-l4t-kernel
Replaces: nvidia-l4t-kernel
Section: kernel
Priority: optional
EOF

cat <<EOF > "$PKG_DIR/DEBIAN/postinst"
#!/bin/bash
set -e

EXTLINUX_CONF="/boot/extlinux/extlinux.conf"

# Update only within the 'LABEL primary' block
sed -i "/^LABEL primary/,/^$/ {
    s|^\\s*LINUX .*|    LINUX /boot/Image-$KERNEL_VERSION|
    s|^\\s*INITRD .*|    INITRD /boot/initrd.img-$KERNEL_VERSION|
    s|^\\s*FDT .*|    FDT /boot/dtb/tegra234-p3701-0000-p3737-0000-$KERNEL_VERSION.dtb|
}" "\$EXTLINUX_CONF"

depmod "$KERNEL_VERSION"
update-initramfs -c -k "$KERNEL_VERSION"
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

echo "Building display driver"
DISPLAY_SCRIPT="$DRIVER_SCRIPTS_DIR/build_display_driver.sh"
"$DISPLAY_SCRIPT" --kernel-sources "$KERNEL_SRC_ROOT" --toolchain "$TOOLCHAIN_ROOT_DIR"
echo ""$DISPLAY_SCRIPT" --kernel-sources "$KERNEL_SRC_ROOT" --toolchain "$TOOLCHAIN_ROOT_DIR" --reuse"

# Copy all built .ko files once
for KO_FILE in "$TMP_DIR/jetson_display_driver/Linux_for_Tegra/source/public/nvdisplay/kernel-open"/*.ko; do
    if [[ -f "$KO_FILE" ]]; then
        echo "Copying $(basename "$KO_FILE") into module tree"
        cp "$KO_FILE" "$DRIVER_OUTPUT_DIR/"
    fi
done

depmod -b "$PKG_DIR" "$KERNEL_VERSION"

OUTPUT_DEB="$TEGRA_DIR/$PKG_NAME.deb"
dpkg-deb --build "$PKG_DIR" "$OUTPUT_DEB"
echo "✅ Debian package created at: $OUTPUT_DEB"

