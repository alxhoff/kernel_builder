#!/bin/bash
#
# integrate_rtl8192eu.sh
#
# Import the Realtek RTL8192EU vendor driver source
# (https://github.com/clnhub/rtl8192eu-linux) directly into a kernel tree
# managed by this repository, so the driver is built whenever the kernel is
# compiled instead of having to be produced separately via
# scripts/rootfs/build_third_party_drivers.sh.
#
# The driver is dropped into drivers/staging/rtl8192eu/ and wired into the
# parent drivers/staging/Kconfig and drivers/staging/Makefile with a new
# CONFIG_RTL8192EU symbol. CONFIG_RTL8192EU=m is enabled in the requested
# defconfig(s).
#
# The script is idempotent: running it again updates the hook lines / defconfig
# without duplicating entries. Use --force to re-import the vendor source over
# an existing drivers/staging/rtl8192eu/ directory.

set -euo pipefail

REPO_URL="https://github.com/clnhub/rtl8192eu-linux.git"
# Default to the upstream repository's default branch (detected at clone time).
# This can be overridden via --ref.
REPO_REF=""
FORCE=0
DEFCONFIGS=("tegra_defconfig" "defconfig")
KERNEL_NAME=""

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
REPO_ROOT="$(realpath "$SCRIPT_DIR/../../..")"
CACHE_DIR="$REPO_ROOT/.cache/rtl8192eu"

show_help() {
    cat <<EOF
Usage: $0 <KERNEL_NAME> [OPTIONS]

Integrate the RTL8192EU vendor driver into kernels/<KERNEL_NAME>/kernel/kernel
as an in-tree staging driver (CONFIG_RTL8192EU=m).

Arguments:
  KERNEL_NAME           Name of the kernel tree under kernels/ (e.g. cartken_5_1_5).

Options:
  --repo <url>          Override the upstream git URL (default: $REPO_URL).
  --ref <ref>           Git ref / branch / tag to import (default: upstream
                        default branch).
  --defconfig <name>    Defconfig to enable CONFIG_RTL8192EU=m in. May be given
                        multiple times. If not specified the script will try
                        each of: ${DEFCONFIGS[*]} (skipping missing ones).
  --skip-defconfig      Do not modify any defconfig.
  --force               Re-import the vendor source even if
                        drivers/staging/rtl8192eu/ already exists.
  -h, --help            Show this help.

Examples:
  $0 cartken_5_1_5
  $0 cartken_5_1_5 --ref master --force
EOF
}

USER_DEFCONFIGS=()
SKIP_DEFCONFIG=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)         REPO_URL="$2"; shift 2 ;;
        --ref)          REPO_REF="$2"; shift 2 ;;
        --defconfig)    USER_DEFCONFIGS+=("$2"); shift 2 ;;
        --skip-defconfig) SKIP_DEFCONFIG=1; shift ;;
        --force)        FORCE=1; shift ;;
        -h|--help)      show_help; exit 0 ;;
        -*)
            echo "Unknown option: $1" >&2
            show_help >&2
            exit 1
            ;;
        *)
            if [[ -z "$KERNEL_NAME" ]]; then
                KERNEL_NAME="$1"
                shift
            else
                echo "Unexpected positional argument: $1" >&2
                exit 1
            fi
            ;;
    esac
done

if [[ -z "$KERNEL_NAME" ]]; then
    echo "Error: KERNEL_NAME is required." >&2
    show_help >&2
    exit 1
fi

KERNEL_ROOT="$REPO_ROOT/kernels/$KERNEL_NAME/kernel/kernel"
if [[ ! -d "$KERNEL_ROOT" ]]; then
    echo "Error: kernel source not found at $KERNEL_ROOT" >&2
    exit 1
fi

STAGING_DIR="$KERNEL_ROOT/drivers/staging"
DRIVER_DIR="$STAGING_DIR/rtl8192eu"
STAGING_KCONFIG="$STAGING_DIR/Kconfig"
STAGING_MAKEFILE="$STAGING_DIR/Makefile"

if [[ ! -f "$STAGING_KCONFIG" || ! -f "$STAGING_MAKEFILE" ]]; then
    echo "Error: $STAGING_DIR does not look like a kernel staging directory." >&2
    exit 1
fi

echo "==> Kernel tree:        $KERNEL_ROOT"
echo "==> Staging driver dir: $DRIVER_DIR"
echo "==> Upstream:           $REPO_URL ${REPO_REF:-<default branch>}"

############################################
# 1. Fetch / update the vendor source cache.
############################################
mkdir -p "$CACHE_DIR"
if [[ ! -d "$CACHE_DIR/.git" ]]; then
    echo "==> Cloning $REPO_URL into $CACHE_DIR"
    git clone --depth 50 "$REPO_URL" "$CACHE_DIR"
else
    echo "==> Updating cached repository in $CACHE_DIR"
    git -C "$CACHE_DIR" remote set-url origin "$REPO_URL"
    if [[ -n "$REPO_REF" ]]; then
        git -C "$CACHE_DIR" fetch --depth 50 origin "$REPO_REF"
    else
        git -C "$CACHE_DIR" fetch --depth 50 origin
    fi
fi

# Resolve the effective ref. When none was requested, fall back to the remote
# default branch (e.g. upstream currently uses "5.11.2.3", not "master").
if [[ -z "$REPO_REF" ]]; then
    DEFAULT_REF="$(git -C "$CACHE_DIR" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    DEFAULT_REF="${DEFAULT_REF#origin/}"
    if [[ -z "$DEFAULT_REF" ]]; then
        DEFAULT_REF="$(git -C "$CACHE_DIR" rev-parse --abbrev-ref HEAD)"
    fi
    REPO_REF="$DEFAULT_REF"
fi

echo "==> Checking out $REPO_REF"
if ! git -C "$CACHE_DIR" checkout --quiet "$REPO_REF" 2>/dev/null; then
    if ! git -C "$CACHE_DIR" checkout --quiet -B "$REPO_REF" "origin/$REPO_REF" 2>/dev/null; then
        echo "Error: unable to check out ref '$REPO_REF' from $REPO_URL" >&2
        exit 1
    fi
fi
RESOLVED_SHA="$(git -C "$CACHE_DIR" rev-parse HEAD)"
echo "==> Imported commit:    $RESOLVED_SHA"

############################################
# 2. Copy the vendor source into drivers/staging/rtl8192eu/.
############################################
if [[ -d "$DRIVER_DIR" && "$FORCE" -eq 0 ]]; then
    echo "==> $DRIVER_DIR already exists; skipping source copy (use --force to re-import)."
else
    if [[ -d "$DRIVER_DIR" ]]; then
        echo "==> Removing existing $DRIVER_DIR (--force)"
        rm -rf "$DRIVER_DIR"
    fi
    mkdir -p "$DRIVER_DIR"
    echo "==> Copying vendor sources"
    # Copy everything except .git and build artefacts.
    tar -C "$CACHE_DIR" \
        --exclude='.git' \
        --exclude='.github' \
        --exclude='*.ko' \
        --exclude='*.o' \
        --exclude='*.mod' \
        --exclude='*.mod.c' \
        --exclude='*.cmd' \
        --exclude='.tmp_versions' \
        --exclude='Module.symvers' \
        --exclude='modules.order' \
        -cf - . | tar -C "$DRIVER_DIR" -xf -
    # Record the imported commit for traceability.
    printf 'upstream: %s\nref:      %s\ncommit:   %s\n' \
        "$REPO_URL" "$REPO_REF" "$RESOLVED_SHA" \
        > "$DRIVER_DIR/IMPORTED_FROM"
fi

############################################
# 2b. Apply in-tree build fixes to the vendor source.
############################################
#
# The upstream clnhub/rtl8192eu-linux tree is designed for an out-of-tree
# build and has a few issues when compiled as part of the kernel with the
# kernel's strict warning set (-Werror). We patch these here instead of
# carrying a separate patch file so that the fixes are re-applied every
# time the vendor source is (re-)imported.
apply_vendor_fixes() {
    local driver_dir="$1"
    local usb_ops="$driver_dir/os_dep/linux/usb_ops_linux.c"
    local vendor_makefile="$driver_dir/Makefile"

    # Fix 1: recvbuf2recvframe() is forward-declared 'static' in
    # os_dep/linux/usb_ops_linux.c but its actual definition (in
    # hal/rtl8192e/usb/usb_ops_linux.c) has external linkage. The 'static'
    # is wrong; remove it so the declaration matches the definition. With
    # -Werror enabled the bogus 'static' forward decl aborts the build
    # with "'recvbuf2recvframe' used but never defined".
    if [[ -f "$usb_ops" ]] && grep -q '^static int recvbuf2recvframe(PADAPTER padapter, void \*ptr);' "$usb_ops"; then
        sed -i 's/^static int recvbuf2recvframe(PADAPTER padapter, void \*ptr);$/int recvbuf2recvframe(PADAPTER padapter, void *ptr);/' "$usb_ops"
        echo "==> Patched $(realpath --relative-to="$REPO_ROOT" "$usb_ops") (removed stray 'static' on recvbuf2recvframe decl)"
    fi

    # Fix 2: Disable MP (Manufacturing/Production) mode. It pulls in
    # os_dep/linux/ioctl_mp.c and core/rtw_mp.c, which use variable-length
    # arrays and other patterns rejected by the kernel's -Werror set.
    # MP mode is a lab/RF test facility and is not needed for normal
    # Wi-Fi operation on the robot.
    if [[ -f "$vendor_makefile" ]] && grep -qE '^CONFIG_MP_INCLUDED[[:space:]]*=[[:space:]]*y' "$vendor_makefile"; then
        sed -i -E 's/^CONFIG_MP_INCLUDED[[:space:]]*=[[:space:]]*y/CONFIG_MP_INCLUDED = n/' "$vendor_makefile"
        echo "==> Patched $(realpath --relative-to="$REPO_ROOT" "$vendor_makefile") (CONFIG_MP_INCLUDED = n)"
    fi
}

apply_vendor_fixes "$DRIVER_DIR"

############################################
# 3. Write the in-tree Kconfig.
############################################
KCONFIG_FILE="$DRIVER_DIR/Kconfig"
echo "==> Writing $KCONFIG_FILE"
cat > "$KCONFIG_FILE" <<'EOF'
# SPDX-License-Identifier: GPL-2.0
config RTL8192EU
	tristate "Realtek RTL8192EU/RTL8192EUS USB Wi-Fi driver (vendor)"
	depends on WLAN && USB && CFG80211
	depends on m
	help
	  Realtek vendor driver for RTL8192EU / RTL8192EUS USB Wi-Fi adapters,
	  imported from https://github.com/clnhub/rtl8192eu-linux into this
	  kernel tree so that it is built together with the kernel.

	  The resulting module is called 8192eu.

	  If unsure, say M.
EOF

############################################
# 4. Hook into drivers/staging/Kconfig.
############################################
KCONFIG_LINE='source "drivers/staging/rtl8192eu/Kconfig"'
if grep -Fq "$KCONFIG_LINE" "$STAGING_KCONFIG"; then
    echo "==> $STAGING_KCONFIG already sources rtl8192eu/Kconfig"
else
    echo "==> Adding 'source rtl8192eu/Kconfig' to $STAGING_KCONFIG"
    # Insert right before the closing 'endif # STAGING' line.
    awk -v line="$KCONFIG_LINE" '
        BEGIN { inserted = 0 }
        /^endif[[:space:]]*#[[:space:]]*STAGING/ && !inserted {
            print ""
            print line
            inserted = 1
        }
        { print }
        END {
            if (!inserted) {
                print ""
                print line
            }
        }
    ' "$STAGING_KCONFIG" > "$STAGING_KCONFIG.new"
    mv "$STAGING_KCONFIG.new" "$STAGING_KCONFIG"
fi

############################################
# 5. Hook into drivers/staging/Makefile.
############################################
MAKEFILE_LINE='obj-$(CONFIG_RTL8192EU)		+= rtl8192eu/'
if grep -Fq 'CONFIG_RTL8192EU' "$STAGING_MAKEFILE"; then
    echo "==> $STAGING_MAKEFILE already references CONFIG_RTL8192EU"
else
    echo "==> Adding obj-\$(CONFIG_RTL8192EU) to $STAGING_MAKEFILE"
    # Append next to the other realtek staging driver lines if possible.
    if grep -q 'CONFIG_R8188EU' "$STAGING_MAKEFILE"; then
        awk -v line="$MAKEFILE_LINE" '
            { print }
            /CONFIG_R8188EU/ && !inserted { print line; inserted = 1 }
        ' "$STAGING_MAKEFILE" > "$STAGING_MAKEFILE.new"
        mv "$STAGING_MAKEFILE.new" "$STAGING_MAKEFILE"
    else
        printf '%s\n' "$MAKEFILE_LINE" >> "$STAGING_MAKEFILE"
    fi
fi

############################################
# 6. Enable CONFIG_RTL8192EU=m in defconfig(s).
############################################
enable_defconfig_symbol() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "==> Defconfig $file not present, skipping"
        return 0
    fi
    # Remove any existing stale RTL8192EU lines, then append a clean one.
    if grep -Eq '^#?\s*CONFIG_RTL8192EU[ =]' "$file"; then
        sed -i -E '/^#?\s*CONFIG_RTL8192EU([ =]|$)/d' "$file"
    fi
    # Insert next to CONFIG_R8188EU if it exists, otherwise append.
    if grep -q '^CONFIG_R8188EU=' "$file"; then
        awk '
            { print }
            /^CONFIG_R8188EU=/ && !inserted {
                print "CONFIG_RTL8192EU=m"
                inserted = 1
            }
        ' "$file" > "$file.new"
        mv "$file.new" "$file"
    else
        printf 'CONFIG_RTL8192EU=m\n' >> "$file"
    fi
    echo "==> Enabled CONFIG_RTL8192EU=m in $(realpath --relative-to="$REPO_ROOT" "$file")"
}

if [[ "$SKIP_DEFCONFIG" -eq 0 ]]; then
    CONFIGS_TO_PATCH=()
    if [[ ${#USER_DEFCONFIGS[@]} -gt 0 ]]; then
        CONFIGS_TO_PATCH=("${USER_DEFCONFIGS[@]}")
    else
        CONFIGS_TO_PATCH=("${DEFCONFIGS[@]}")
    fi
    for cfg in "${CONFIGS_TO_PATCH[@]}"; do
        enable_defconfig_symbol "$KERNEL_ROOT/arch/arm64/configs/$cfg"
    done
fi

cat <<EOF

Integration complete.

Next steps:
  1. Rebuild the kernel, e.g.:
       ./scripts/kernel_builder/compile_and_package.sh $KERNEL_NAME --localversion <your-tag>
     The 8192eu.ko module will be produced by the in-tree build and end up in
     the generated Debian package at:
       /lib/modules/<version>/kernel/drivers/staging/rtl8192eu/8192eu.ko

  2. If you use scripts/rootfs/build_third_party_drivers.sh to build a full
     rootfs, remove "rtl8192eu" from the THIRD_PARTY_DRIVERS list so the driver
     is not built twice. The 88x2bu driver remains handled there.
EOF
