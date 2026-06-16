#!/usr/bin/env bash
# Install NVIDIA L4T x-tools into storage/toolchains/aarch64-none-linux-gnu/13.2/
# so kernel_builder.py can use --toolchain-name aarch64-none-linux-gnu --toolchain-version 13.2
set -euo pipefail

JP7_TOOLCHAIN_URL="${JP7_TOOLCHAIN_URL:-https://developer.download.nvidia.com/embedded/L4T/r38_Release_v2.0/release/x-tools.tbz2}"
TOOLCHAIN_NAME="aarch64-none-linux-gnu"
TOOLCHAIN_VERSION="13.2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
INSTALL_ROOT="${REPO_ROOT}/storage/toolchains/${TOOLCHAIN_NAME}/${TOOLCHAIN_VERSION}"
GCC_PATH="${INSTALL_ROOT}/bin/${TOOLCHAIN_NAME}-gcc"

if [[ -x "$GCC_PATH" ]]; then
	echo "JP7 toolchain ready: $GCC_PATH"
	exit 0
fi

mkdir -p "$INSTALL_ROOT"
archive="${INSTALL_ROOT}/x-tools.tbz2"
if [[ ! -f "$archive" ]]; then
	echo "Downloading JP7 Crosstool-NG toolchain..."
	wget -c "$JP7_TOOLCHAIN_URL" -O "$archive"
fi

echo "Extracting JP7 toolchain into $INSTALL_ROOT..."
tar -xjf "$archive" -C "$INSTALL_ROOT"

x_tools_bin="${INSTALL_ROOT}/x-tools/${TOOLCHAIN_NAME}/bin"
if [[ ! -x "${x_tools_bin}/${TOOLCHAIN_NAME}-gcc" ]]; then
	echo "Error: expected ${x_tools_bin}/${TOOLCHAIN_NAME}-gcc after extract" >&2
	exit 1
fi

mkdir -p "${INSTALL_ROOT}/bin"
ln -sfn "../x-tools/${TOOLCHAIN_NAME}/bin/${TOOLCHAIN_NAME}-gcc" "${INSTALL_ROOT}/bin/${TOOLCHAIN_NAME}-gcc"
ln -sfn "../x-tools/${TOOLCHAIN_NAME}/bin/${TOOLCHAIN_NAME}-g++" "${INSTALL_ROOT}/bin/${TOOLCHAIN_NAME}-g++"
ln -sfn "../x-tools/${TOOLCHAIN_NAME}/bin/${TOOLCHAIN_NAME}-ld" "${INSTALL_ROOT}/bin/${TOOLCHAIN_NAME}-ld"
ln -sfn "../x-tools/${TOOLCHAIN_NAME}/bin/${TOOLCHAIN_NAME}-ar" "${INSTALL_ROOT}/bin/${TOOLCHAIN_NAME}-ar"
ln -sfn "../x-tools/${TOOLCHAIN_NAME}/bin/${TOOLCHAIN_NAME}-nm" "${INSTALL_ROOT}/bin/${TOOLCHAIN_NAME}-nm"
ln -sfn "../x-tools/${TOOLCHAIN_NAME}/bin/${TOOLCHAIN_NAME}-objcopy" "${INSTALL_ROOT}/bin/${TOOLCHAIN_NAME}-objcopy"
ln -sfn "../x-tools/${TOOLCHAIN_NAME}/bin/${TOOLCHAIN_NAME}-objdump" "${INSTALL_ROOT}/bin/${TOOLCHAIN_NAME}-objdump"
ln -sfn "../x-tools/${TOOLCHAIN_NAME}/bin/${TOOLCHAIN_NAME}-strip" "${INSTALL_ROOT}/bin/${TOOLCHAIN_NAME}-strip"
ln -sfn "../x-tools/${TOOLCHAIN_NAME}/bin/${TOOLCHAIN_NAME}-ranlib" "${INSTALL_ROOT}/bin/${TOOLCHAIN_NAME}-ranlib"

echo "JP7 toolchain ready: $GCC_PATH"
