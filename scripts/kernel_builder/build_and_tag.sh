#!/bin/bash

# One-shot interactive kernel build, package, and tag.
#
# Guides you through selecting a kernel, generating a localversion and tag,
# entering a description, then compiles, packages, and tags everything
# automatically. Designed to replace the manual two-step process of
# compile_and_package.sh + kernel_tags.sh tag.
#
# Usage: ./build_and_tag.sh [KERNEL_NAME] [options]

set -e

SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
REPO_ROOT="$(realpath "$SCRIPT_DIR/..")"
KERNELS_DIR="$REPO_ROOT/kernels"
COMPILE_SCRIPT="$SCRIPT_DIR/kernel_builder/compile_and_package.sh"
TAGS_SCRIPT="$SCRIPT_DIR/kernel_builder/kernel_tags.sh"
TAGS_FILE="$REPO_ROOT/kernel_tags.json"

# ── helpers ──────────────────────────────────────────────────────────────────

kernel_name_to_localversion_base() {
  # cartken_5_1_5_realsense -> cartken5.1.5realsense
  # cartken_6_2             -> cartken6.2
  echo "$1" | sed 's/_\([0-9]\)/.\1/g; s/_//g; s/\.\([0-9]\)/\1/'
}

date_suffix() {
  date +%d%m%y
}

list_kernels() {
  local i=1
  for d in "$KERNELS_DIR"/*/; do
    [ -d "$d" ] || continue
    local name
    name=$(basename "$d")
    [ "$name" = ".gitkeep" ] && continue
    echo "  $i) $name"
    i=$((i + 1))
  done
}

get_kernel_names() {
  local names=()
  for d in "$KERNELS_DIR"/*/; do
    [ -d "$d" ] || continue
    local name
    name=$(basename "$d")
    [ "$name" = ".gitkeep" ] && continue
    names+=("$name")
  done
  echo "${names[@]}"
}

prompt() {
  local varname="$1" prompt_text="$2" default="$3"
  local input
  if [ -n "$default" ]; then
    read -rp "$prompt_text [$default]: " input
    printf -v "$varname" '%s' "${input:-$default}"
  else
    read -rp "$prompt_text: " input
    printf -v "$varname" '%s' "$input"
  fi
}

show_help() {
  cat <<'EOF'
One-Shot Kernel Build & Tag
============================

Usage: build_and_tag.sh [KERNEL_NAME] [options]

Interactively builds a kernel, packages it as a .deb, and tags it for version
tracking — all in a single step. Automatically generates a localversion and
tag name based on today's date.

When run without options, interactively prompts for all required information.
Options can pre-fill values to skip specific prompts.

Options:
  --soc <type>               SOC type: orin or xavier (publishes to production_kernels)
  --localversion <str>       Override the auto-generated localversion
  --tag <name>               Override the auto-generated tag name
  --description <text>       Build description (skips interactive prompt)
  --config <file>            Kernel config file (default: defconfig)
  --dtb-name <name>          Device tree blob filename
  --status <status>          Initial tag status (default: development)
  --threads <N>              Number of build threads
  --toolchain-name <name>    Cross-compile toolchain name
  --toolchain-version <ver>  Toolchain version (default: 9.3)
  --build-dtb                Also build device tree blobs
  --build-modules            Also build kernel modules separately
  --overlays <list>          Comma-separated DTBO overlay files
  --no-tag                   Skip tagging (just build and package)
  --no-publish               Skip publishing to production_kernels
  --help                     Show this help

Interactive flow (values can be pre-filled with options above):
  1. Select kernel source directory
  2. Select SOC type (orin/xavier)
  3. Auto-generate localversion (kernel base + DDMMYY date)
  4. Enter a description of what this build changes
  5. Build → Package → Tag → Publish (all automatic)

Examples:
  # Fully interactive
  build_and_tag.sh

  # Pre-select kernel and SOC
  build_and_tag.sh cartken_5_1_5_realsense --soc orin

  # Pre-fill description, skip that prompt
  build_and_tag.sh cartken_5_1_5_realsense --soc orin \
    --description "Added temp sensor I2C driver"

  # Fully non-interactive
  build_and_tag.sh cartken_5_1_5_realsense --soc orin \
    --description "Added temp sensor I2C driver"
EOF
  exit 0
}

# ── argument parsing ─────────────────────────────────────────────────────────

KERNEL_NAME=""
SOC=""
LOCALVERSION=""
TAG_NAME=""
DESCRIPTION=""
CONFIG="defconfig"
DTB_NAME=""
TAG_STATUS="development"
THREADS=""
TOOLCHAIN_NAME=""
TOOLCHAIN_VERSION=""
BUILD_DTB=false
BUILD_MODULES=false
OVERLAYS=""
NO_TAG=false
NO_PUBLISH=false

# First positional arg is kernel name (if not a flag)
if [ -n "$1" ] && [[ "$1" != --* ]]; then
  KERNEL_NAME="$1"
  shift
fi

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --help|-h)              show_help ;;
    --soc)                  SOC="$2"; shift 2 ;;
    --localversion)         LOCALVERSION="$2"; shift 2 ;;
    --tag)                  TAG_NAME="$2"; shift 2 ;;
    --description)          DESCRIPTION="$2"; shift 2 ;;
    --config)               CONFIG="$2"; shift 2 ;;
    --dtb-name)             DTB_NAME="$2"; shift 2 ;;
    --status)               TAG_STATUS="$2"; shift 2 ;;
    --threads)              THREADS="$2"; shift 2 ;;
    --toolchain-name)       TOOLCHAIN_NAME="$2"; shift 2 ;;
    --toolchain-version)    TOOLCHAIN_VERSION="$2"; shift 2 ;;
    --build-dtb)            BUILD_DTB=true; shift ;;
    --build-modules)        BUILD_MODULES=true; shift ;;
    --overlays)             OVERLAYS="$2"; shift 2 ;;
    --no-tag)               NO_TAG=true; shift ;;
    --no-publish)           NO_PUBLISH=true; shift ;;
    *) echo "Error: Unknown option '$1'. Run with --help for usage."; exit 1 ;;
  esac
done

# ── interactive flow ─────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║         Kernel Build & Tag                       ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# Step 1: Select kernel
if [ -z "$KERNEL_NAME" ]; then
  echo "Available kernel sources:"
  echo ""
  list_kernels
  echo ""

  local_kernels=($(get_kernel_names))
  if [ ${#local_kernels[@]} -eq 0 ]; then
    echo "Error: No kernel sources found under kernels/"
    exit 1
  fi

  read -rp "Select kernel [1-${#local_kernels[@]}]: " selection

  if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#local_kernels[@]} ]; then
    KERNEL_NAME="${local_kernels[$((selection - 1))]}"
  else
    echo "Invalid selection."
    exit 1
  fi
fi

if [ ! -d "$KERNELS_DIR/$KERNEL_NAME" ]; then
  echo "Error: Kernel source '$KERNEL_NAME' not found under kernels/"
  exit 1
fi

echo "  Kernel: $KERNEL_NAME"

# Step 2: SOC type
if [ -z "$SOC" ] && [ "$NO_TAG" = false ] && [ "$NO_PUBLISH" = false ]; then
  echo ""
  echo "  SOC type (determines production_kernels/<soc>/ path):"
  echo "    1) orin"
  echo "    2) xavier"
  echo ""
  read -rp "  Select SOC [1-2] (or press Enter to skip): " soc_selection
  case "$soc_selection" in
    1) SOC="orin" ;;
    2) SOC="xavier" ;;
    "") echo "  Skipping production publish (no SOC selected)." ;;
    *) echo "  Invalid selection, skipping production publish." ;;
  esac
  [ -n "$SOC" ] && echo "  SOC: $SOC"
fi

# Step 3: Generate localversion (renumbered from interactive flow)
LV_BASE=$(kernel_name_to_localversion_base "$KERNEL_NAME")
DATE_TAG=$(date_suffix)

if [ -z "$LOCALVERSION" ]; then
  default_lv="${LV_BASE}.${DATE_TAG}"
  echo ""
  echo "  Auto-generated localversion: $default_lv"
  echo "  (format: <kernel-base>.<DDMMYY>)"
  echo ""
  prompt LOCALVERSION "  Localversion" "$default_lv"
fi

# Step 3: Generate tag name
if [ -z "$TAG_NAME" ] && [ "$NO_TAG" = false ]; then
  default_tag="$DATE_TAG"

  # Check if this tag already exists
  if [ -f "$TAGS_FILE" ] && command -v jq &>/dev/null; then
    if jq -e --arg tag "$default_tag" '.[] | select(.tag == $tag)' "$TAGS_FILE" > /dev/null 2>&1; then
      n=2
      while jq -e --arg tag "${default_tag}.${n}" '.[] | select(.tag == $tag)' "$TAGS_FILE" > /dev/null 2>&1; do
        n=$((n + 1))
      done
      default_tag="${default_tag}.${n}"
    fi
  fi

  prompt TAG_NAME "  Tag name" "$default_tag"
fi

# Step 4: Description
if [ -z "$DESCRIPTION" ] && [ "$NO_TAG" = false ]; then
  echo ""
  echo "  What does this build add/change/fix?"
  prompt DESCRIPTION "  Description" ""

  if [ -z "$DESCRIPTION" ]; then
    echo "  Warning: No description provided. Continuing anyway."
  fi
fi

# Step 5: Config
echo ""
prompt CONFIG "  Kernel config" "$CONFIG"

# Step 6: Show summary and confirm
echo ""
echo "┌──────────────────────────────────────────────────"
echo "│ Build Summary"
echo "├──────────────────────────────────────────────────"
JETPACK_VERSION=""
if [ -n "$KERNEL_NAME" ]; then
  JETPACK_VERSION=$(echo "$KERNEL_NAME" | sed 's/^[^0-9]*//' | sed 's/_[a-zA-Z].*//' | tr '_' '.')
fi

echo "│ Kernel:        $KERNEL_NAME"
echo "│ Localversion:  $LOCALVERSION"
echo "│ Config:        $CONFIG"
if [ "$NO_TAG" = false ]; then
  echo "│ Tag:           $TAG_NAME"
  echo "│ Status:        $TAG_STATUS"
  if [ -n "$DESCRIPTION" ]; then
    echo "│ Description:   $DESCRIPTION"
  fi
fi
[ -n "$SOC" ] && echo "│ SOC:           $SOC (Jetpack $JETPACK_VERSION)"
[ -n "$SOC" ] && echo "│ Publish to:    production_kernels/$SOC/$JETPACK_VERSION/"
[ -n "$DTB_NAME" ]     && echo "│ DTB:           $DTB_NAME"
[ -n "$THREADS" ]      && echo "│ Threads:       $THREADS"
[ "$BUILD_DTB" = true ] && echo "│ Build DTBs:    yes"
[ "$BUILD_MODULES" = true ] && echo "│ Build Modules: yes"
echo "└──────────────────────────────────────────────────"
echo ""

# ── build ────────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Step 1/$([ "$NO_TAG" = false ] && echo "2" || echo "1"): Building and packaging kernel..."
echo "═══════════════════════════════════════════════════"
echo ""

BUILD_CMD="\"$COMPILE_SCRIPT\" \"$KERNEL_NAME\" --localversion \"$LOCALVERSION\" --config \"$CONFIG\""

[ -n "$THREADS" ]            && BUILD_CMD="$BUILD_CMD --threads \"$THREADS\""
[ -n "$DTB_NAME" ]           && BUILD_CMD="$BUILD_CMD --dtb-name \"$DTB_NAME\""
[ "$BUILD_DTB" = true ]      && BUILD_CMD="$BUILD_CMD --build-dtb"
[ "$BUILD_MODULES" = true ]  && BUILD_CMD="$BUILD_CMD --build-modules"
[ -n "$OVERLAYS" ]           && BUILD_CMD="$BUILD_CMD --overlays \"$OVERLAYS\""
[ -n "$TOOLCHAIN_NAME" ]     && BUILD_CMD="$BUILD_CMD --toolchain-name \"$TOOLCHAIN_NAME\""
[ -n "$TOOLCHAIN_VERSION" ]  && BUILD_CMD="$BUILD_CMD --toolchain-version \"$TOOLCHAIN_VERSION\""

if ! eval $BUILD_CMD; then
  echo ""
  echo "Build failed."
  exit 1
fi

echo ""
echo "Build and packaging completed successfully."

# ── tag ──────────────────────────────────────────────────────────────────────

if [ "$NO_TAG" = false ]; then
  echo ""
  echo "═══════════════════════════════════════════════════"
  echo "  Step 2/2: Tagging build..."
  echo "═══════════════════════════════════════════════════"
  echo ""

  TAG_CMD="\"$TAGS_SCRIPT\" tag \"$TAG_NAME\" --kernel \"$KERNEL_NAME\" --localversion \"$LOCALVERSION\""
  TAG_CMD="$TAG_CMD --config \"$CONFIG\" --status \"$TAG_STATUS\""
  [ -n "$DESCRIPTION" ] && TAG_CMD="$TAG_CMD --description \"$DESCRIPTION\""
  [ -n "$DTB_NAME" ]    && TAG_CMD="$TAG_CMD --dtb-name \"$DTB_NAME\""
  [ -n "$SOC" ] && [ "$NO_PUBLISH" = false ] && TAG_CMD="$TAG_CMD --soc \"$SOC\""
  [ "$NO_PUBLISH" = true ] && TAG_CMD="$TAG_CMD --no-publish"

  # Use --force in case tag already exists (e.g. rebuilding same day)
  if [ -f "$TAGS_FILE" ] && command -v jq &>/dev/null; then
    if jq -e --arg tag "$TAG_NAME" '.[] | select(.tag == $tag)' "$TAGS_FILE" > /dev/null 2>&1; then
      echo "Tag '$TAG_NAME' already exists, overwriting..."
      TAG_CMD="$TAG_CMD --force"
    fi
  fi

  if ! eval $TAG_CMD; then
    echo ""
    echo "Warning: Tagging failed, but the kernel was built and packaged successfully."
    echo "You can tag manually with:"
    echo "  $TAGS_SCRIPT tag $TAG_NAME --kernel $KERNEL_NAME --localversion $LOCALVERSION"
    exit 0
  fi

  echo ""
  echo "═══════════════════════════════════════════════════"
  echo "  Done!"
  echo "═══════════════════════════════════════════════════"
  echo ""
  echo "  Kernel:       $KERNEL_NAME"
  echo "  Localversion: $LOCALVERSION"
  echo "  Tag:          $TAG_NAME"
  [ -n "$SOC" ] && echo "  Published:    production_kernels/$SOC/$JETPACK_VERSION/"
  echo ""
  echo "  To deploy:"
  echo "    $TAGS_SCRIPT deploy $TAG_NAME --ip <address>"
  echo ""
  echo "  To deploy to robots:"
  echo "    $TAGS_SCRIPT deploy $TAG_NAME --robots 1,2,3 --robot-ip-prefix \"10.42.0.\""
  echo ""
else
  echo ""
  echo "═══════════════════════════════════════════════════"
  echo "  Done! (tagging skipped)"
  echo "═══════════════════════════════════════════════════"
  echo ""
  echo "  Kernel:       $KERNEL_NAME"
  echo "  Localversion: $LOCALVERSION"
fi
