#!/bin/bash

set -e

CROSS_PREFIX="aarch64-buildroot-linux-gnu-"
TOOLCHAIN_PATH=""
KERNEL_SOURCES_DIR=""
TARGET_BSP=""

show_help() {
    echo "Usage: $0 --toolchain <path> --kernel-sources <path> [--output-dir <path>]"
    echo "Options:"
    echo "  --toolchain PATH       Path to the cross-compilation toolchain, ie. path $TO_HERE/bin/aarch64... (required)"
    echo "  --kernel-sources PATH  Path to the kernel source directory (required)"
	echo "  --target-bsp NAME      BSP identifier to append to LOCALVERSION (required)"
    exit 0
}

REUSE_KERNEL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --toolchain)
            TOOLCHAIN_PATH=$(realpath "$2")
            shift 2
            ;;
        --kernel-sources)
            KERNEL_SOURCES_DIR=$(realpath "$2")
            shift 2
            ;;
        --reuse)
            REUSE_KERNEL=true
            shift
            ;;
		--target-bsp)
			TARGET_BSP="$2"
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

if [[ -z "$TOOLCHAIN_PATH" || -z "$KERNEL_SOURCES_DIR" || -z "$TARGET_BSP" ]]; then
	echo "Error: --toolchain, --kernel-sources, and --target-bsp are required."
	exit 1
fi

L4T_DIR="$KERNEL_SOURCES_DIR/.."
WORK_DIR="$L4T_DIR/jetson_display_driver"
KERNEL_OUT_DIR="$WORK_DIR/kernel_out"
LOCALVERSION="-cartken${TARGET_BSP}"

mkdir -p "$WORK_DIR"

# pick the right kernel-src folder name
if [[ "$TARGET_BSP" == "6.0DP" || "$TARGET_BSP" == "6.2" ]]; then
    KERNEL_FOLDER="kernel-jammy-src"
else
    KERNEL_FOLDER="kernel-5.10"
fi

KERNEL_TARGET_DIR="$WORK_DIR/kernel_src/kernel/$KERNEL_FOLDER"

if [[ -d "$KERNEL_TARGET_DIR" && -n "$(ls -A "$KERNEL_TARGET_DIR")" ]]; then
	echo "Kernel source already exists at '$KERNEL_TARGET_DIR' and is not empty. Skipping copy."
else
	cp -r $KERNEL_SOURCES_DIR "$WORK_DIR/kernel_src"
	SOURCE_DIR=$(find "$WORK_DIR/kernel_src/kernel/" -mindepth 1 -maxdepth 1 -type d -name "kernel*" ! -name "$KERNEL_FOLDER" | head -n 1)
	if [ -n "$SOURCE_DIR" ]; then
		mv "$SOURCE_DIR" "$KERNEL_TARGET_DIR"
		echo "Folder renamed to 'kernel-5.10'."
	else
		echo "No matching folder found to rename."
	fi
fi

case "$TARGET_BSP" in
    5.1.2)
        BSP_SOURCES_TAR_URL="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/sources/public_sources.tbz2"
        ;;
    5.1.3)
        BSP_SOURCES_TAR_URL="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/sources/public_sources.tbz2"
        ;;
    5.1.4)
        BSP_SOURCES_TAR_URL="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.0/sources/public_sources.tbz2"
        ;;
    5.1.5)
        BSP_SOURCES_TAR_URL="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.1/sources/public_sources.tbz2"
        ;;
    6.0DP)
        BSP_SOURCES_TAR_URL="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v2.0/sources/public_sources.tbz2"
        ;;
    6.2)
        BSP_SOURCES_TAR_URL="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/sources/public_sources.tbz2"
        ;;
    *)
        echo "Unsupported target BSP: $TARGET_BSP"
        exit 1
        ;;
esac
BSP_SOURCES_TAR="$WORK_DIR/public_sources.tbz2"
if [[ "$TARGET_BSP" == "6.0DP" || "$TARGET_BSP" == "6.2" ]]; then
    NVDISPLAY_TAR_DIR="$WORK_DIR/Linux_for_Tegra/source"
else
    NVDISPLAY_TAR_DIR="$WORK_DIR/Linux_for_Tegra/source/public"
fi
NVDISPLAY_TAR="$NVDISPLAY_TAR_DIR/nvidia_kernel_display_driver_source.tbz2"
NVDISPLAY_SOURCE_DIR="$NVDISPLAY_TAR_DIR/nvdisplay"

if [[ ! -d "$NVDISPLAY_TAR_DIR" ]]; then
	echo "Downloading and extracting public sources..."
	wget -O "$BSP_SOURCES_TAR" "$BSP_SOURCES_TAR_URL"
	tar -xpf "$BSP_SOURCES_TAR" -C "$WORK_DIR"
fi

if [[ ! -d "$NVDISPLAY_SOURCE_DIR" ]]; then
	echo "Extracting display driver sources..."
	tar -xpf "$NVDISPLAY_TAR" -C "$NVDISPLAY_TAR_DIR"
fi

CROSS_COMPILE_PATH="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}"

if [[ "$REUSE_KERNEL" == "true" ]]; then
	echo "Skipping kernel cleanup (mrproper) and reusing previous build..."
else
	echo "Cleaning kernel sources and output directory..."
	make -C "$KERNEL_TARGET_DIR" -j "$(nproc)" ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE_PATH} LOCALVERSION="$LOCALVERSION" mrproper

	if [[ -d "$KERNEL_OUT_DIR" ]]; then
		rm -rf "$KERNEL_OUT_DIR"
	fi
	mkdir -p "$KERNEL_OUT_DIR"
fi

echo "Applying defconfig"
make -C "$KERNEL_TARGET_DIR" O=$KERNEL_OUT_DIR -j "$(nproc)" ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE_PATH} LOCALVERSION="$LOCALVERSION" defconfig

echo "Tegra defconfig applied, building kernel"
make -C "$KERNEL_TARGET_DIR" O=$KERNEL_OUT_DIR -j "$(nproc)" ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE_PATH} LOCALVERSION="$LOCALVERSION"

echo "Kernel built. Building NVIDIA Jetson display driver..."

IGNORE_MISSING_MODULE_SYMVERS=1 make VERBOSE=1 -C "$NVDISPLAY_SOURCE_DIR" modules \
	TARGET_ARCH=aarch64 ARCH=arm64 \
	LOCALVERSION="$LOCALVERSION" \
	CC="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}gcc" \
	LD="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}ld.bfd" \
	AR="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}ar" \
	CXX="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}g++" \
	OBJCOPY="${TOOLCHAIN_PATH}/bin/${CROSS_PREFIX}objcopy" \
	SYSOUT="$KERNEL_OUT_DIR" SYSSRC="$KERNEL_TARGET_DIR"

echo "Build complete. Output is in: $KERNEL_OUT_DIR"

echo "Packaging kernel modules into a Debian package..."

# Extract kernel version from the Image file
KERNEL_IMAGE="$KERNEL_OUT_DIR/arch/arm64/boot/Image"
if [[ -f "$KERNEL_IMAGE" ]]; then
    KERNEL_VERSION=$(strings "$KERNEL_IMAGE" | grep -oP "Linux version \K[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9._]+)?" | head -n 1)
else
    echo "Error: Kernel Image not found at $KERNEL_IMAGE"
    exit 1
fi

PACKAGE_NAME="nvdisplay-${KERNEL_VERSION}"
PACKAGE_DIR="$(pwd)/${PACKAGE_NAME}"
DEB_PACKAGE="$(pwd)/${PACKAGE_NAME}.deb"

rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR/DEBIAN"
DISP_MODULE_DIR="$PACKAGE_DIR/lib/modules/${KERNEL_VERSION}/extra/opensrc-disp"
mkdir -p "$DISP_MODULE_DIR"

cp "$NVDISPLAY_SOURCE_DIR/kernel-open/nvidia.ko" "$DISP_MODULE_DIR/"
cp "$NVDISPLAY_SOURCE_DIR/kernel-open/nvidia-drm.ko" "$DISP_MODULE_DIR/"
cp "$NVDISPLAY_SOURCE_DIR/kernel-open/nvidia-modeset.ko" "$DISP_MODULE_DIR/"

cat <<EOF > "$PACKAGE_DIR/DEBIAN/control"
Package: $PACKAGE_NAME
Version: 1.0
Architecture: arm64
Maintainer: Alex Hoffman <alxhoff@cartken.com>
Description: NVIDIA kernel modules for Jetson, compiled for kernel $KERNEL_VERSION
EOF

cat <<EOF > "$PACKAGE_DIR/DEBIAN/postinst"
#!/bin/bash
set -e
echo "Running depmod for kernel ${KERNEL_VERSION}..."
depmod -a ${KERNEL_VERSION}
EOF
chmod 755 "$PACKAGE_DIR/DEBIAN/postinst"

dpkg-deb --build "$PACKAGE_DIR" "$DEB_PACKAGE"

echo "Debian package created: $DEB_PACKAGE"

