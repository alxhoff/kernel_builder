#!/bin/bash

# Ensure JP7 kernel_src contains every OOT path listed in nvbuild.sh's
# kernel_src_build_env.sh (including unifiedgpudisp).

set -e

extract_jp7_kernel_src_components() {
	local source_root="$1"
	local kernel_src_dir="$2"

	if [[ -f "$source_root/kernel_oot_modules_src.tbz2" && ! -d "$kernel_src_dir/nvidia-oot" ]]; then
		echo "Extracting kernel out-of-tree modules..."
		tar -xjf "$source_root/kernel_oot_modules_src.tbz2" -C "$kernel_src_dir"
	fi

	if [[ -f "$source_root/nvidia_kernel_display_driver_source.tbz2" && ! -d "$kernel_src_dir/nvdisplay" ]]; then
		echo "Extracting NVIDIA kernel display driver source (nvdisplay)..."
		tar -xjf "$source_root/nvidia_kernel_display_driver_source.tbz2" -C "$kernel_src_dir"
	fi

	if [[ -f "$source_root/nvidia_unified_gpu_display_driver_source.tbz2" && ! -d "$kernel_src_dir/unifiedgpudisp" ]]; then
		echo "Extracting NVIDIA unified GPU display driver source (unifiedgpudisp)..."
		tar -xjf "$source_root/nvidia_unified_gpu_display_driver_source.tbz2" -C "$kernel_src_dir"
	fi
}

supplement_jp7_kernel_src_from_public_sources() {
	local public_sources="$1"
	local kernel_src_dir="$2"
	local tmp_dir
	local source_root

	if [[ ! -f "$public_sources" ]]; then
		echo "Error: JP7 kernel_src is incomplete and $public_sources was not found." >&2
		return 1
	fi

	tmp_dir="$(mktemp -d)"
	echo "Supplementing JP7 kernel_src from $(basename "$public_sources")..."
	tar -xjf "$public_sources" -C "$tmp_dir"
	source_root="$tmp_dir/Linux_for_Tegra/source"

	if [[ ! -d "$kernel_src_dir/kernel" && -f "$source_root/kernel_src.tbz2" ]]; then
		echo "Extracting kernel_src.tbz2..."
		tar -xjf "$source_root/kernel_src.tbz2" -C "$kernel_src_dir"
	fi

	extract_jp7_kernel_src_components "$source_root" "$kernel_src_dir"
	rm -rf "$tmp_dir"
}

resolve_public_sources_archive() {
	local hint="${1:-}"
	local dir

	if [[ -n "$hint" && -f "$hint" ]]; then
		echo "$hint"
		return 0
	fi

	dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	for candidate in \
		"$dir/../downloads/public_sources.tbz2" \
		"$dir/../../downloads/public_sources.tbz2"; do
		if [[ -f "$candidate" ]]; then
			echo "$(realpath "$candidate")"
			return 0
		fi
	done

	return 1
}

ensure_jp7_kernel_src_complete() {
	local kernel_src_dir="$1"
	local public_sources="${2:-}"
	local missing=()
	local required_dirs=(
		nvethernetrm
		nvgpu
		nvidia-oot
		hwpm
		hardware
		nvdisplay
		unifiedgpudisp
	)

	if [[ -z "$public_sources" ]]; then
		public_sources="$(resolve_public_sources_archive || true)"
	fi

	for dir in "${required_dirs[@]}"; do
		if [[ ! -d "$kernel_src_dir/$dir" ]]; then
			missing+=("$dir")
		fi
	done
	if [[ ! -d "$kernel_src_dir/build/nvidia-public/devicetree" ]]; then
		missing+=("build/nvidia-public/devicetree")
	fi

	if [[ ${#missing[@]} -eq 0 ]]; then
		return 0
	fi

	echo "kernel_src is missing JP7 components required by nvbuild.sh: ${missing[*]}"
	if [[ -z "$public_sources" || ! -f "$public_sources" ]]; then
		echo "Error: public_sources.tbz2 not found. Place it under scripts/flash/rootfs_prep/downloads/." >&2
		return 1
	fi
	supplement_jp7_kernel_src_from_public_sources "$public_sources" "$kernel_src_dir"

	missing=()
	for dir in "${required_dirs[@]}"; do
		if [[ ! -d "$kernel_src_dir/$dir" ]]; then
			missing+=("$dir")
		fi
	done
	if [[ ! -d "$kernel_src_dir/build/nvidia-public/devicetree" ]]; then
		missing+=("build/nvidia-public/devicetree")
	fi
	if [[ ${#missing[@]} -gt 0 ]]; then
		echo "Error: kernel_src is still missing JP7 components after supplement: ${missing[*]}" >&2
		return 1
	fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	case "${1:-}" in
		complete)
			ensure_jp7_kernel_src_complete "$2" "${3:-}"
			;;
		*)
			echo "Usage: $0 complete <kernel_src_dir> [public_sources.tbz2]" >&2
			exit 1
			;;
	esac
fi
