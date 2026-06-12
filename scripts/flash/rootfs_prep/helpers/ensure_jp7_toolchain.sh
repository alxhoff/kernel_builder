#!/usr/bin/env bash
# Ensure NVIDIA L4T Crosstool-NG GCC 13.2 (aarch64-none-linux-gnu) is available for JP7 builds.
set -euo pipefail

JP7_TOOLCHAIN_URL="https://developer.download.nvidia.com/embedded/L4T/r38_Release_v2.0/release/x-tools.tbz2"
JP7_TOOLCHAIN_PREFIX_REL="x-tools/aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-"
JP7_TOOLCHAIN_DOCKER_ROOT="/opt/nvidia-l4t-toolchain"

jp7_toolchain_gcc_path() {
	local root="$1"
	echo "${root}/${JP7_TOOLCHAIN_PREFIX_REL}gcc"
}

resolve_jp7_toolchain_install_root() {
	if [[ -x "$(jp7_toolchain_gcc_path "$JP7_TOOLCHAIN_DOCKER_ROOT")" ]]; then
		echo "$JP7_TOOLCHAIN_DOCKER_ROOT"
		return 0
	fi

	local helper_dir script_dir
	helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	script_dir="$(cd "$helper_dir/.." && pwd)"
	echo "${JP7_TOOLCHAIN_INSTALL_ROOT:-$script_dir/toolchains/jp7}"
}

ensure_jp7_toolchain() {
	local install_root gcc_path archive
	install_root="$(resolve_jp7_toolchain_install_root)"
	gcc_path="$(jp7_toolchain_gcc_path "$install_root")"

	if [[ -x "$gcc_path" ]]; then
		JP7_TOOLCHAIN_ROOT="$install_root"
		JP7_CROSS_COMPILE="${install_root}/${JP7_TOOLCHAIN_PREFIX_REL}"
		export JP7_TOOLCHAIN_ROOT JP7_CROSS_COMPILE
		echo "Using JP7 toolchain: $gcc_path"
		return 0
	fi

	if [[ "$install_root" == "$JP7_TOOLCHAIN_DOCKER_ROOT" ]]; then
		echo "Error: JP7 toolchain not found in Docker image at $install_root" >&2
		echo "Rebuild the JP7 docker image with: $0 --docker --rebuild --jetpack 7.2" >&2
		return 1
	fi

	mkdir -p "$install_root"
	archive="${install_root}/x-tools.tbz2"
	if [[ ! -f "$archive" ]]; then
		echo "Downloading JP7 Crosstool-NG toolchain..."
		wget -c "$JP7_TOOLCHAIN_URL" -O "$archive"
	fi

	echo "Extracting JP7 toolchain into $install_root..."
	tar -xjf "$archive" -C "$install_root"

	if [[ ! -x "$gcc_path" ]]; then
		echo "Error: JP7 toolchain extraction failed; expected $gcc_path" >&2
		return 1
	fi

	JP7_TOOLCHAIN_ROOT="$install_root"
	JP7_CROSS_COMPILE="${install_root}/${JP7_TOOLCHAIN_PREFIX_REL}"
	export JP7_TOOLCHAIN_ROOT JP7_CROSS_COMPILE
	echo "JP7 toolchain ready: $gcc_path"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	ensure_jp7_toolchain
	echo "CROSS_COMPILE=$JP7_CROSS_COMPILE"
fi
