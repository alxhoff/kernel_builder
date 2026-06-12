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

fetch_pinmux_dir() {
  local pinmux_src_dir="$1"
  local git_ref="${2:-master}"

  TMP_DIR="$(mktemp -d)"
  cleanup() { rm -rf "$TMP_DIR"; }
  trap cleanup EXIT

  git init "$TMP_DIR"
  cd "$TMP_DIR"
  git remote add origin https://github.com/alxhoff/kernel_builder.git
  git config core.sparseCheckout true
  echo "$pinmux_src_dir/" >> .git/info/sparse-checkout
  git pull origin "$git_ref"
  echo "$TMP_DIR/$pinmux_src_dir"
}

apply_jp7_cartken_pinmux_overlay() {
  local l4t_dir="$1"
  local overlay_src="$2"
  local pinmux_dtsi="$overlay_src/bootloader/generic/BCT/Orin-jetson_agx_orin-pinmux.dtsi"
  local gpio_dtsi="$overlay_src/bootloader/Orin-jetson_agx_orin-gpio-default.dtsi"
  local generic_bct="$l4t_dir/bootloader/generic/BCT"
  local p3701_conf="$l4t_dir/p3701.conf.common"

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

PINMUX_SRC=""
if repo_root="$(find_kernel_builder_root)"; then
  PINMUX_SRC="$repo_root/$PINMUX_SRC_DIR"
fi

if [[ ! -d "$PINMUX_SRC" ]]; then
  git_ref="master"
  [[ "$major_version" -eq 7 ]] && git_ref="jetpack7"
  echo "Local $PINMUX_SRC_DIR not found; fetching from origin/$git_ref"
  PINMUX_SRC="$(fetch_pinmux_dir "$PINMUX_SRC_DIR" "$git_ref")"
fi

if [[ "$major_version" -eq 7 ]]; then
  apply_jp7_cartken_pinmux_overlay "$L4T_DIR" "$PINMUX_SRC"
else
  apply_legacy_pinmux_tree "$L4T_DIR" "$PINMUX_SRC"
fi
