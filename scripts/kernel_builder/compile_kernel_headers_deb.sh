#!/bin/bash

# General workflow for building a kernel Debian package.
# Usage: ./compile_kernel_deb.sh [KERNEL_NAME] [OPTIONS]

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_BUILDER_PATH="$SCRIPT_DIR/../kernel_builder.py"

set -e

# Ensure kernel name is provided
if [ -z "$1" ]; then
  echo "Error: Kernel name must be provided as the first argument."
  echo "Usage: ./compile_kernel_deb.sh [KERNEL_NAME] [OPTIONS]"
  echo "Use --help for more information."
  exit 1
fi

KERNEL_NAME="$1"
shift # Shift arguments to parse the rest of the options

# Initialize arguments
CONFIG_ARG=""
LOCALVERSION_ARG=""
LOCALVERSION_VAL=""
THREADS_ARG=""
DTB_NAME_ARG="--dtb-name tegra234-p3701-0000-p3737-0000.dtb"  # Default DTB name
HOST_BUILD_ARG=""
DRY_RUN_ARG=""
BUILD_DTB_ARG=""
TOOLCHAIN_NAME_ARG="--toolchain-name aarch64-buildroot-linux-gnu"
TOOLCHAIN_VERSION_ARG="--toolchain-version 9.3"

# Function to display help message
show_help() {
    echo "Usage: ./compile_kernel_deb.sh [KERNEL_NAME] [OPTIONS]"
    echo ""
    echo "This script builds a kernel headers Debian package."
    echo ""
    echo "Arguments:"
    echo "  KERNEL_NAME                    Specify the name of the kernel to be built (e.g., 'jetson')."
    echo ""
    echo "Options:"
    echo "  --config <config-file>         Specify the kernel configuration file to use (e.g., defconfig, tegra_defconfig)."
    echo "  --localversion <version>       Set a local version string to append to the kernel version (e.g., -custom_version)."
    echo "  --threads <number>             Number of threads to use for compilation (default: use all available cores)."
    echo "  --toolchain-name <name>        Specify the toolchain to use (default: aarch64-buildroot-linux-gnu)."
    echo "  --toolchain-version <version>  Specify the toolchain version to use (default: 9.3)."
    echo "  --dtb-name <dtb-name>          Specify the name of the Device Tree Blob (DTB) file to be copied alongside the compiled kernel (default: tegra234-p3701-0000-p3737-0000.dtb)."
    echo "  --build-dtb                    Build the Device Tree Blob (DTB) separately using 'make dtbs'."
    echo "  --host-build                   Compile the kernel directly on the host instead of using Docker."
    echo "  --dry-run                      Print the commands without executing them."
    echo "  --help                         Display this help message and exit."
    echo ""
    echo "Examples:"
    echo "  Build a kernel headers Debian package for 'jetson' with default settings:"
    echo "    ./compile_kernel_deb.sh jetson"
    echo ""
    echo "  Build a kernel headers Debian package using a specific kernel config and local version:"
    echo "    ./compile_kernel_deb.sh jetson --config tegra_defconfig --localversion custom_version"
    echo ""
    echo "  Build a kernel headers Debian package with 8 threads and specify a DTB file:"
    echo "    ./compile_kernel_deb.sh jetson --threads 8 --dtb-name tegra234-p3701-0000-p3737-0000.dtb"
    echo ""
    echo "  Build a kernel headers Debian package directly on the host system instead of using Docker:"
    echo "    ./compile_kernel_deb.sh jetson --host-build"
    echo ""
    exit 0
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --config)
      if [ -n "$2" ]; then
        CONFIG_ARG="--config $2"
        shift 2
      else
        echo "Error: --config requires a value"
        exit 1
      fi
      ;;
    --localversion)
      if [ -n "$2" ]; then
        LOCALVERSION_VAL="$2"
        LOCALVERSION_ARG="--localversion "$2""
        shift 2
      else
        echo "Error: --localversion requires a value"
        exit 1
      fi
      ;;
    --threads)
      if [ -n "$2" ]; then
        THREADS_ARG="--threads $2"
        shift 2
      else
        echo "Error: --threads requires a value"
        exit 1
      fi
      ;;
    --dtb-name)
      if [ -n "$2" ]; then
        DTB_NAME_ARG="--dtb-name $2"
        shift 2
      else
        echo "Error: --dtb-name requires a value"
        exit 1
      fi
      ;;
    --toolchain-name)
      if [ -n "$2" ]; then
        TOOLCHAIN_NAME_ARG="--toolchain-name $2"
        shift 2
      else
        echo "Error: --toolchain-name requires a value"
        exit 1
      fi
      ;;
    --toolchain-version)
      if [ -n "$2" ]; then
        TOOLCHAIN_VERSION_ARG="--toolchain-version $2"
        shift 2
      else
        echo "Error: --toolchain-version requires a value"
        exit 1
      fi
      ;;
    --build-dtb)
      BUILD_DTB_ARG="--build-dtb"
      shift
      ;;
    --host-build)
      HOST_BUILD_ARG="--host-build"
      shift
      ;;
    --dry-run)
      DRY_RUN_ARG="--dry-run"
      shift
      ;;
    --help)
      show_help
      ;;
    *)
      echo "Unknown parameter: $1"
      echo "Use --help for more information."
      exit 1
      ;;
  esac
done

# Compile the kernel using kernel_builder.py
export DEBEMAIL="user@example.com"
export DEBFULLNAME="Builder"
COMMAND="python3 "$KERNEL_BUILDER_PATH" compile --build-target headers_install --kernel-name "$KERNEL_NAME" --arch arm64 $TOOLCHAIN_NAME_ARG $TOOLCHAIN_VERSION_ARG $CONFIG_ARG $THREADS_ARG $LOCALVERSION_ARG $DTB_NAME_ARG $HOST_BUILD_ARG $DRY_RUN_ARG $BUILD_DTB_ARG"

# Execute the command
echo "Running: $COMMAND"
if [[ -n "$DRY_RUN_ARG" ]]; then
  echo "[Dry-run] Command: $COMMAND"
else
  eval $COMMAND
fi

if [[ -n "$DRY_RUN_ARG" ]]; then
  echo "[Dry-run] Skipping debian package creation."
  exit 0
fi

echo "Creating Debian package for kernel headers..."

KERNEL_SRC_DIR="kernels/$KERNEL_NAME/kernel/kernel"

if [ ! -f "$KERNEL_SRC_DIR/Makefile" ]; then
    echo "Error: Makefile not found in $KERNEL_SRC_DIR"
    exit 1
fi

VERSION=$(grep '^VERSION = ' "$KERNEL_SRC_DIR/Makefile" | awk '{print $3}')
PATCHLEVEL=$(grep '^PATCHLEVEL = ' "$KERNEL_SRC_DIR/Makefile" | awk '{print $3}')
SUBLEVEL=$(grep '^SUBLEVEL = ' "$KERNEL_SRC_DIR/Makefile" | awk '{print $3}')
EXTRAVERSION=$(grep '^EXTRAVERSION = ' "$KERNEL_SRC_DIR/Makefile" | cut -d'=' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

if [ -z "$VERSION" ] || [ -z "$PATCHLEVEL" ] || [ -z "$SUBLEVEL" ]; then
    echo "Error: Could not determine kernel version from Makefile."
    exit 1
fi

KERNEL_VERSION="${VERSION}.${PATCHLEVEL}.${SUBLEVEL}${EXTRAVERSION}"
if [ -n "$LOCALVERSION_VAL" ]; then
  KERNEL_VERSION="${KERNEL_VERSION}-${LOCALVERSION_VAL}"
fi

PKG_NAME="linux-headers-${KERNEL_VERSION}"
PKG_DIR="debian_pkg"

rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/DEBIAN"
mkdir -p "$PKG_DIR/usr/src/${PKG_NAME}"

HEADERS_DIR="kernels/$KERNEL_NAME/headers"
cp -r "$HEADERS_DIR/include" "$PKG_DIR/usr/src/${PKG_NAME}/"
# The headers_install target in kernel creates arch-specific headers under the arch/$ARCH folder
# so we need to copy that as well.
if [ -d "$HEADERS_DIR/arch" ]; then
    cp -r "$HEADERS_DIR/arch" "$PKG_DIR/usr/src/${PKG_NAME}/"
fi


cat << EOF > "$PKG_DIR/DEBIAN/control"
Package: ${PKG_NAME}
Version: ${KERNEL_VERSION}
Architecture: arm64
Maintainer: $DEBFULLNAME <$DEBEMAIL>
Description: Linux kernel headers for ${KERNEL_VERSION}
EOF

# Create postinst script
POSTINST_SCRIPT="$PKG_DIR/DEBIAN/postinst"
cat << EOF > "$POSTINST_SCRIPT"
#!/bin/sh
set -e
mkdir -p /lib/modules/${KERNEL_VERSION}
ln -sfn /usr/src/${PKG_NAME} /lib/modules/${KERNEL_VERSION}/build
exit 0
EOF

chmod +x "$POSTINST_SCRIPT"

dpkg-deb --build "$PKG_DIR" "${PKG_NAME}_arm64.deb"
rm -rf "$PKG_DIR"

echo "Debian package created: ${PKG_NAME}_arm64.deb"