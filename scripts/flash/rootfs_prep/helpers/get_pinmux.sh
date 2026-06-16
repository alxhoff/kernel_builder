#!/usr/bin/env bash
set -euo pipefail

# --- Help function ---
show_help() {
  echo "Usage: $0 --l4t-dir /path/to/Linux_for_Tegra --jetpack-version <version>"
  echo
  echo "Options:"
  echo "  --l4t-dir PATH          Path to your L4T directory (Linux_for_Tegra)."
  echo "  --jetpack-version       The JetPack version (e.g., 5.1.2, 6.0DP, 7.2)."
  echo "  --help                  Show this help message and exit."
}

FETCH_TMP_DIR=""

cleanup_fetch_tmp() {
  if [[ -n "${FETCH_TMP_DIR}" && -d "${FETCH_TMP_DIR}" ]]; then
    rm -rf "${FETCH_TMP_DIR}"
  fi
}

find_kernel_builder_root() {
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/sources/pinmux" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

resolve_local_pinmux_src() {
  local pinmux_leaf="$1"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if repo_root="$(find_kernel_builder_root)"; then
    if [[ -d "$repo_root/sources/pinmux/$pinmux_leaf" ]]; then
      echo "$repo_root/sources/pinmux/$pinmux_leaf"
      return 0
    fi
  fi

  if [[ -n "${L4T_DIR:-}" && -d "${L4T_DIR}/.cartken_pinmux" ]]; then
    echo "${L4T_DIR}/.cartken_pinmux"
    return 0
  fi

  local candidate
  for candidate in \
    "$script_dir/pinmux/$pinmux_leaf" \
    "$script_dir/../helpers/pinmux/$pinmux_leaf" \
    "/workspace/helpers/pinmux/$pinmux_leaf"; do
    if [[ -d "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

fetch_pinmux_dir() {
  local pinmux_src_dir="$1"
  local git_ref="${2:-master}"

  cleanup_fetch_tmp
  FETCH_TMP_DIR="$(mktemp -d)"

  git -C "$FETCH_TMP_DIR" init -q
  git -C "$FETCH_TMP_DIR" remote add origin https://github.com/alxhoff/kernel_builder.git
  git -C "$FETCH_TMP_DIR" config core.sparseCheckout true
  echo "$pinmux_src_dir/" >> "$FETCH_TMP_DIR/.git/info/sparse-checkout"
  git -C "$FETCH_TMP_DIR" pull -q origin "$git_ref"

  echo "$FETCH_TMP_DIR/$pinmux_src_dir"
}

jp7_pinmux_overlay_dtsi() {
  echo "$1/bootloader/generic/BCT/Orin-jetson_agx_orin-pinmux.dtsi"
}

fetch_remote_pinmux_src() {
  local pinmux_src_dir="$1"
  local major_version="$2"
  local git_ref fetched pinmux_dtsi

  if [[ "$major_version" -eq 7 ]]; then
    for git_ref in jetpack7 master; do
      echo "get_pinmux.sh: fetching $pinmux_src_dir from origin/$git_ref" >&2
      fetched="$(fetch_pinmux_dir "$pinmux_src_dir" "$git_ref")"
      pinmux_dtsi="$(jp7_pinmux_overlay_dtsi "$fetched")"
      if [[ -f "$pinmux_dtsi" ]]; then
        echo "$fetched"
        return 0
      fi
      echo "get_pinmux.sh: origin/$git_ref missing $pinmux_dtsi" >&2
      cleanup_fetch_tmp
    done
    return 1
  fi

  echo "get_pinmux.sh: fetching $pinmux_src_dir from origin/master" >&2
  fetch_pinmux_dir "$pinmux_src_dir" master
}

apply_jp7_cartken_pinmux_overlay() {
  local l4t_dir="$1"
  local overlay_src="$2"
  local pinmux_dtsi gpio_dtsi generic_bct p3701_conf

  pinmux_dtsi="$(jp7_pinmux_overlay_dtsi "$overlay_src")"
  gpio_dtsi="$overlay_src/bootloader/Orin-jetson_agx_orin-gpio-default.dtsi"
  generic_bct="$l4t_dir/bootloader/generic/BCT"
  p3701_conf="$l4t_dir/p3701.conf.common"

  [[ -f "$pinmux_dtsi" ]] || {
    echo "Error: missing cartken pinmux overlay $pinmux_dtsi" >&2
    exit 1
  }

  mkdir -p "$generic_bct"
  cp "$pinmux_dtsi" "$generic_bct/"

  if [[ -f "$gpio_dtsi" ]]; then
    cp "$gpio_dtsi" "$l4t_dir/bootloader/"
  fi

  # JP7/R39: keep NVIDIA board confs intact; only point flash at cartken pinmux.
  if [[ -f "$p3701_conf" ]]; then
    sed -i 's/^PINMUX_CONFIG=.*/PINMUX_CONFIG="Orin-jetson_agx_orin-pinmux.dtsi";/' "$p3701_conf"
    # Repair BSPs previously overwritten by the JP5-derived 7.X pinmux tree.
    sed -i 's/^target_board="t186ref";/target_board="generic";/' "$p3701_conf"
    sed -i 's/EMMC_BCT=/EMC_BCT=/g' "$p3701_conf"
  fi

  echo "Applied JP7 cartken pinmux overlay to $l4t_dir"
}

apply_legacy_pinmux_tree() {
  local l4t_dir="$1"
  local overlay_src="$2"
  echo "Merging $(basename "$(dirname "$overlay_src")")/$(basename "$overlay_src") into $l4t_dir"
  cp -rT "$overlay_src" "$l4t_dir"
}

# --- Parse arguments ---
L4T_DIR=""
JETPACK_VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --l4t-dir)
      L4T_DIR="$(realpath "$2")"
      shift 2
      ;;
    --jetpack-version)
      JETPACK_VERSION="$2"
      shift 2
      ;;
    --help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      show_help
      exit 1
      ;;
  esac
done

if [[ -z "$L4T_DIR" ]]; then
  echo "Error: --l4t-dir is required"
  show_help
  exit 1
fi

if [[ -z "$JETPACK_VERSION" ]]; then
  echo "Error: --jetpack-version is required"
  show_help
  exit 1
fi

major_version="${JETPACK_VERSION%%.*}"
case "$major_version" in
  5) PINMUX_SRC_DIR="sources/pinmux/5.X" ;;
  6) PINMUX_SRC_DIR="sources/pinmux/6.X" ;;
  7) PINMUX_SRC_DIR="sources/pinmux/7.X" ;;
  *)
    echo "Error: Unsupported JetPack major version: $major_version"
    exit 1
    ;;
esac
PINMUX_LEAF="${PINMUX_SRC_DIR##*/}"

PINMUX_SRC=""
if PINMUX_SRC="$(resolve_local_pinmux_src "$PINMUX_LEAF")"; then
  echo "get_pinmux.sh: using local pinmux at $PINMUX_SRC"
else
  echo "get_pinmux.sh: local $PINMUX_SRC_DIR not found" >&2
  if ! PINMUX_SRC="$(fetch_remote_pinmux_src "$PINMUX_SRC_DIR" "$major_version")"; then
    echo "Error: could not fetch $PINMUX_SRC_DIR from origin (tried jetpack7 and master)" >&2
    exit 1
  fi
fi

if [[ "$major_version" -eq 7 ]]; then
  echo "get_pinmux.sh: JP7 overlay mode (cartken pinmux only; NVIDIA board confs preserved)"
  apply_jp7_cartken_pinmux_overlay "$L4T_DIR" "$PINMUX_SRC"
else
  apply_legacy_pinmux_tree "$L4T_DIR" "$PINMUX_SRC"
fi

cleanup_fetch_tmp
