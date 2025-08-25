#!/usr/bin/env bash
set -euo pipefail

# --- Help function ---
show_help() {
  echo "Usage: $0 --l4t-dir /path/to/Linux_for_Tegra --jetpack-version <version>"
  echo
  echo "Options:"
  echo "  --l4t-dir PATH          Path to your L4T directory (Linux_for_Tegra)."
  echo "  --jetpack-version       The JetPack version (e.g., 5.1.2, 6.0DP)."
  echo "  --help                  Show this help message and exit."
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

# --- Determine pinmux source directory ---
major_version="${JETPACK_VERSION%%.*}"
if [[ "$major_version" -eq 5 ]]; then
  PINMUX_SRC_DIR="pinmux/5.X"
elif [[ "$major_version" -eq 6 ]]; then
  PINMUX_SRC_DIR="pinmux/6.X"
else
  echo "Error: Unsupported JetPack major version: $major_version"
  exit 1
fi

# --- Setup temporary directory ---
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# --- Clone only the needed folder using sparse checkout ---
git init "$TMP_DIR"
cd "$TMP_DIR"
git remote add origin https://github.com/alxhoff/kernel_builder.git
git config core.sparseCheckout true
echo "$PINMUX_SRC_DIR/" >> .git/info/sparse-checkout
git pull origin master

# --- Copy and merge pinmux contents into $L4T_DIR ---
echo "Merging $PINMUX_SRC_DIR directory into $L4T_DIR"
cp -rT "$TMP_DIR/$PINMUX_SRC_DIR" "$L4T_DIR"

