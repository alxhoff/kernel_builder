#!/usr/bin/env bash
set -euo pipefail

# --- Help function ---
show_help() {
  echo "Usage: $0 --l4t-dir /path/to/Linux_for_Tegra"
  echo
  echo "Options:"
  echo "  --l4t-dir PATH   Path to your L4T directory (Linux_for_Tegra)."
  echo "  --help           Show this help message and exit."
}

# --- Parse arguments ---
L4T_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --l4t-dir)
      L4T_DIR="$(realpath "$2")"
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

# --- Setup temporary directory ---
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# --- Clone only the needed folder using sparse checkout ---
git init "$TMP_DIR"
cd "$TMP_DIR"
git remote add origin https://github.com/alxhoff/kernel_builder.git
git config core.sparseCheckout true
echo "pinmux/" >> .git/info/sparse-checkout
git pull origin master

# --- Copy and merge pinmux contents into $L4T_DIR ---
echo "Merging pinmux directory into $L4T_DIR"
cp -rT "$TMP_DIR/pinmux" "$L4T_DIR"

