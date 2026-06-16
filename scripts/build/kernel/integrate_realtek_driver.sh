#!/bin/bash
#
# integrate_realtek_driver.sh
#
# Generic helper that imports a Realtek "rtw"-style vendor Wi-Fi driver source
# tree (e.g. rtl8192eu, rtl88x2bu) directly into a kernel managed by this
# repository, so the driver builds together with the kernel instead of having
# to be produced separately by scripts/rootfs/build_third_party_drivers.sh.
#
# Driver-specific knobs (upstream URL, in-tree directory name, Kconfig symbol,
# module name, post-import patches) live in the driver registry below. To add
# another driver, register it there and add a matching apply_vendor_fixes_*
# function if needed.
#
# The script is idempotent: re-running it updates the hooks / defconfig
# without duplicating entries. Use --force to re-import the vendor source
# over an existing in-tree copy.

set -euo pipefail

############################################
# Driver registry
############################################
# Each driver has:
#   _REPO   - upstream git URL
#   _DIR    - directory name under drivers/staging/ (and cache subdir)
#   _SYMBOL - Kconfig symbol (e.g. RTL8192EU)
#   _MODULE - resulting kernel module name (e.g. 8192eu)
#   _DESC   - one-line description used in the generated Kconfig prompt
#
# Per-driver post-import source patches are applied by
# apply_vendor_fixes_<driver>() further down.

declare -A DRIVER_REPO=(
    [rtl8192eu]="https://github.com/clnhub/rtl8192eu-linux.git"
    [rtl88x2bu]="https://github.com/cilynx/rtl88x2bu.git"
)
declare -A DRIVER_DIR=(
    [rtl8192eu]="rtl8192eu"
    [rtl88x2bu]="rtl88x2bu"
)
declare -A DRIVER_SYMBOL=(
    [rtl8192eu]="RTL8192EU"
    [rtl88x2bu]="RTL8822BU"
)
declare -A DRIVER_MODULE=(
    [rtl8192eu]="8192eu"
    [rtl88x2bu]="88x2bu"
)
declare -A DRIVER_DESC=(
    [rtl8192eu]="Realtek RTL8192EU/RTL8192EUS USB Wi-Fi driver (vendor)"
    [rtl88x2bu]="Realtek RTL8822BU/RTL88x2BU USB Wi-Fi driver (vendor)"
)

# NOTE on rtl88x2bu / RTL8822BU:
# The NVIDIA L4T kernel tree at kernel/nvidia/drivers/net/wireless/realtek/
# also ships an rtl8822bu directory, but its vendor source dates from 2019
# and predates kernel 5.6 (proc_ops) and 5.8 (cfg80211 mgmt frame
# registrations) API changes, so it does not compile on kernel 5.10. We
# therefore disable that copy in the NVIDIA Kconfig/Makefile and use the
# maintained cilynx fork imported here instead.

############################################
# Defaults / argument parsing
############################################
DRIVER=""
KERNEL_NAME=""
REPO_URL_OVERRIDE=""
REPO_REF=""
FORCE=0
SKIP_DEFCONFIG=0
DEFAULT_DEFCONFIGS=("tegra_defconfig" "defconfig")
USER_DEFCONFIGS=()

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
# This script lives at scripts/build/kernel/, so the repo root is three
# levels up.
REPO_ROOT="$(realpath "$SCRIPT_DIR/../../..")"

show_help() {
    cat <<EOF
Usage: $0 <KERNEL_NAME> --driver <name> [OPTIONS]

Integrate a Realtek vendor Wi-Fi driver into storage/kernels/<KERNEL_NAME>/kernel/<src>/
as an in-tree staging driver (kernel-noble on JP7, kernel-jammy-src or kernel on older BSPs).

Arguments:
  KERNEL_NAME           Name of the kernel tree under storage/kernels/ (e.g. cartken_5_1_5).

Required:
  --driver <name>       Which driver to integrate. Supported: ${!DRIVER_REPO[@]}.

Options:
  --repo <url>          Override the upstream git URL for the selected driver.
  --ref <ref>           Git ref / branch / tag to import (default: upstream
                        default branch).
  --defconfig <name>    Defconfig to enable CONFIG_<SYMBOL>=m in. May be given
                        multiple times. Defaults to: ${DEFAULT_DEFCONFIGS[*]}.
  --skip-defconfig      Do not modify any defconfig.
  --force               Re-import vendor source even if the in-tree directory
                        already exists.
  -h, --help            Show this help.

Examples:
  $0 cartken_5_1_5 --driver rtl8192eu
  $0 cartken_5_1_5 --driver rtl88x2bu --force
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --driver)        DRIVER="$2"; shift 2 ;;
        --repo)          REPO_URL_OVERRIDE="$2"; shift 2 ;;
        --ref)           REPO_REF="$2"; shift 2 ;;
        --defconfig)     USER_DEFCONFIGS+=("$2"); shift 2 ;;
        --skip-defconfig) SKIP_DEFCONFIG=1; shift ;;
        --force)         FORCE=1; shift ;;
        -h|--help)       show_help; exit 0 ;;
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

if [[ -z "$DRIVER" ]]; then
    echo "Error: --driver <name> is required." >&2
    show_help >&2
    exit 1
fi

if [[ -z "${DRIVER_REPO[$DRIVER]:-}" ]]; then
    echo "Error: unsupported driver '$DRIVER'. Supported: ${!DRIVER_REPO[@]}." >&2
    exit 1
fi

REPO_URL="${REPO_URL_OVERRIDE:-${DRIVER_REPO[$DRIVER]}}"
DRIVER_DIRNAME="${DRIVER_DIR[$DRIVER]}"
KCONFIG_SYMBOL="${DRIVER_SYMBOL[$DRIVER]}"
MODULE_NAME="${DRIVER_MODULE[$DRIVER]}"
KCONFIG_DESC="${DRIVER_DESC[$DRIVER]}"

KERNEL_PARENT="$REPO_ROOT/storage/kernels/$KERNEL_NAME/kernel"
KERNEL_ROOT=""
for _subdir in kernel-noble kernel-jammy-src kernel; do
    if [[ -d "$KERNEL_PARENT/$_subdir" ]]; then
        KERNEL_ROOT="$KERNEL_PARENT/$_subdir"
        break
    fi
done
if [[ -z "$KERNEL_ROOT" ]]; then
    echo "Error: kernel source not found under $KERNEL_PARENT (tried kernel-noble, kernel-jammy-src, kernel)" >&2
    exit 1
fi

STAGING_DIR="$KERNEL_ROOT/drivers/staging"
DRIVER_DIR_ABS="$STAGING_DIR/$DRIVER_DIRNAME"
STAGING_KCONFIG="$STAGING_DIR/Kconfig"
STAGING_MAKEFILE="$STAGING_DIR/Makefile"
CACHE_DIR="$REPO_ROOT/.cache/$DRIVER_DIRNAME"

if [[ ! -f "$STAGING_KCONFIG" || ! -f "$STAGING_MAKEFILE" ]]; then
    echo "Error: $STAGING_DIR does not look like a kernel staging directory." >&2
    exit 1
fi

echo "==> Driver:             $DRIVER (CONFIG_$KCONFIG_SYMBOL, module $MODULE_NAME.ko)"
echo "==> Kernel tree:        $KERNEL_ROOT"
echo "==> Staging driver dir: $DRIVER_DIR_ABS"
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
# 2. Copy the vendor source into drivers/staging/<driver>/.
############################################
if [[ -d "$DRIVER_DIR_ABS" && "$FORCE" -eq 0 ]]; then
    echo "==> $DRIVER_DIR_ABS already exists; skipping source copy (use --force to re-import)."
else
    if [[ -d "$DRIVER_DIR_ABS" ]]; then
        echo "==> Removing existing $DRIVER_DIR_ABS (--force)"
        rm -rf "$DRIVER_DIR_ABS"
    fi
    mkdir -p "$DRIVER_DIR_ABS"
    echo "==> Copying vendor sources"
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
        -cf - . | tar -C "$DRIVER_DIR_ABS" -xf -
    printf 'driver:   %s\nupstream: %s\nref:      %s\ncommit:   %s\n' \
        "$DRIVER" "$REPO_URL" "$REPO_REF" "$RESOLVED_SHA" \
        > "$DRIVER_DIR_ABS/IMPORTED_FROM"
fi

############################################
# 2b. Apply per-driver in-tree build fixes.
############################################
# These fixes are common to the rtw vendor codebase (rtl8192eu and
# rtl88x2bu both descend from the same internal codebase):
#
# - Disable MP (Manufacturing/Production) test mode. Its source files use
#   variable-length arrays and other patterns rejected by the kernel's
#   -Werror set. MP mode is a lab/RF self-test facility not needed for
#   normal Wi-Fi operation.
#
# - Fix any 'static' forward-declarations of recvbuf2recvframe in
#   os_dep/linux/usb_ops_linux.c. The actual definition (in the matching
#   hal/<chip>/usb/usb_ops_linux.c) has external linkage; the 'static'
#   prefix on the forward decl is a vendor-source bug that only shows
#   up under the kernel's strict -Werror.
#
# - Strip -Wno-stringop-overread from the vendor Makefile. That option
#   was added in gcc 11; the buildroot toolchain shipped with this repo
#   is gcc 9.3, which rejects it as 'unrecognized command line option'.
#   With the kernel's -Werror in effect, every translation unit fails
#   to compile.
#
# - Disable -Werror for the vendor subtree by appending
#   'ccflags-y += -Wno-error' to the vendor Makefile. The legacy vendor
#   source has many sign-compare and other style issues that the kernel
#   would otherwise reject; this is the same accommodation other staging
#   drivers use.
apply_common_rtw_fixes() {
    local driver_dir="$1"
    local usb_ops="$driver_dir/os_dep/linux/usb_ops_linux.c"
    local vendor_makefile="$driver_dir/Makefile"

    if [[ -f "$usb_ops" ]] && grep -q '^static int recvbuf2recvframe(PADAPTER padapter, void \*ptr);' "$usb_ops"; then
        sed -i 's/^static int recvbuf2recvframe(PADAPTER padapter, void \*ptr);$/int recvbuf2recvframe(PADAPTER padapter, void *ptr);/' "$usb_ops"
        echo "==> Patched $(realpath --relative-to="$REPO_ROOT" "$usb_ops") (removed stray 'static' on recvbuf2recvframe decl)"
    fi

    if [[ -f "$vendor_makefile" ]] && grep -qE '^CONFIG_MP_INCLUDED[[:space:]]*=[[:space:]]*y' "$vendor_makefile"; then
        sed -i -E 's/^CONFIG_MP_INCLUDED[[:space:]]*=[[:space:]]*y/CONFIG_MP_INCLUDED = n/' "$vendor_makefile"
        echo "==> Patched $(realpath --relative-to="$REPO_ROOT" "$vendor_makefile") (CONFIG_MP_INCLUDED = n)"
    fi

    if [[ -f "$vendor_makefile" ]] && grep -q -- '-Wno-stringop-overread' "$vendor_makefile"; then
        sed -i -E '/^[[:space:]]*(EXTRA_CFLAGS|ccflags-y)[[:space:]]*\+=[[:space:]]*-Wno-stringop-overread[[:space:]]*$/d' "$vendor_makefile"
        sed -i 's/[[:space:]]*-Wno-stringop-overread\b//g' "$vendor_makefile"
        echo "==> Patched $(realpath --relative-to="$REPO_ROOT" "$vendor_makefile") (removed -Wno-stringop-overread; gcc <11 doesn't recognise it)"
    fi

    local werror_marker='# integrate_realtek_driver.sh: legacy vendor driver, suppress -Werror'
    if [[ -f "$vendor_makefile" ]] && ! grep -Fq "$werror_marker" "$vendor_makefile"; then
        printf '\n%s\nccflags-y += -Wno-error\n' "$werror_marker" >> "$vendor_makefile"
        echo "==> Patched $(realpath --relative-to="$REPO_ROOT" "$vendor_makefile") (appended ccflags-y += -Wno-error)"
    fi
}

apply_vendor_fixes_rtl8192eu() {
    apply_common_rtw_fixes "$1"
}

apply_vendor_fixes_rtl88x2bu() {
    apply_common_rtw_fixes "$1"
}

case "$DRIVER" in
    rtl8192eu) apply_vendor_fixes_rtl8192eu "$DRIVER_DIR_ABS" ;;
    rtl88x2bu) apply_vendor_fixes_rtl88x2bu "$DRIVER_DIR_ABS" ;;
    *)         apply_common_rtw_fixes "$DRIVER_DIR_ABS" ;;
esac

############################################
# 3. Write the in-tree Kconfig.
############################################
KCONFIG_FILE="$DRIVER_DIR_ABS/Kconfig"
echo "==> Writing $KCONFIG_FILE"
cat > "$KCONFIG_FILE" <<EOF
# SPDX-License-Identifier: GPL-2.0
config $KCONFIG_SYMBOL
	tristate "$KCONFIG_DESC"
	depends on WLAN && USB && CFG80211
	depends on m
	help
	  Vendor driver imported from $REPO_URL into this kernel tree so
	  that it is built together with the kernel.

	  The resulting module is called $MODULE_NAME.

	  If unsure, say M.
EOF

############################################
# 4. Hook into drivers/staging/Kconfig.
############################################
KCONFIG_LINE="source \"drivers/staging/$DRIVER_DIRNAME/Kconfig\""
if grep -Fq "$KCONFIG_LINE" "$STAGING_KCONFIG"; then
    echo "==> $STAGING_KCONFIG already sources $DRIVER_DIRNAME/Kconfig"
else
    echo "==> Adding 'source $DRIVER_DIRNAME/Kconfig' to $STAGING_KCONFIG"
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
MAKEFILE_LINE="obj-\$(CONFIG_$KCONFIG_SYMBOL)		+= $DRIVER_DIRNAME/"
if grep -Fq "CONFIG_$KCONFIG_SYMBOL" "$STAGING_MAKEFILE"; then
    echo "==> $STAGING_MAKEFILE already references CONFIG_$KCONFIG_SYMBOL"
else
    echo "==> Adding obj-\$(CONFIG_$KCONFIG_SYMBOL) to $STAGING_MAKEFILE"
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
# 6. Enable CONFIG_<SYMBOL>=m in defconfig(s).
############################################
enable_defconfig_symbol() {
    local file="$1"
    local symbol="$2"
    if [[ ! -e "$file" ]]; then
        echo "==> Defconfig $file not present, skipping"
        return 0
    fi
    # Some kernel trees ship one defconfig as the canonical file and the
    # other as a symlink (e.g. tegra_defconfig -> defconfig). Resolve
    # symlinks so that we patch the underlying file in place via sed/awk
    # and don't accidentally replace a symlink with a regular copy when we
    # do `mv $file.new $file` further down.
    if [[ -L "$file" ]]; then
        local resolved
        resolved="$(readlink -f -- "$file")"
        echo "==> $file is a symlink to $resolved; patching the target instead"
        file="$resolved"
        if [[ ! -f "$file" ]]; then
            echo "==> Defconfig target $file does not exist, skipping"
            return 0
        fi
    fi
    if grep -Eq "^#?\\s*CONFIG_${symbol}[ =]" "$file"; then
        sed -i -E "/^#?\\s*CONFIG_${symbol}([ =]|$)/d" "$file"
    fi
    if grep -q '^CONFIG_R8188EU=' "$file"; then
        awk -v line="CONFIG_${symbol}=m" '
            { print }
            /^CONFIG_R8188EU=/ && !inserted {
                print line
                inserted = 1
            }
        ' "$file" > "$file.new"
        mv "$file.new" "$file"
    else
        printf 'CONFIG_%s=m\n' "$symbol" >> "$file"
    fi
    echo "==> Enabled CONFIG_${symbol}=m in $(realpath --relative-to="$REPO_ROOT" "$file")"
}

if [[ "$SKIP_DEFCONFIG" -eq 0 ]]; then
    CONFIGS_TO_PATCH=()
    if [[ ${#USER_DEFCONFIGS[@]} -gt 0 ]]; then
        CONFIGS_TO_PATCH=("${USER_DEFCONFIGS[@]}")
    else
        CONFIGS_TO_PATCH=("${DEFAULT_DEFCONFIGS[@]}")
    fi
    for cfg in "${CONFIGS_TO_PATCH[@]}"; do
        enable_defconfig_symbol "$KERNEL_ROOT/arch/arm64/configs/$cfg" "$KCONFIG_SYMBOL"
    done
fi

cat <<EOF

Integration complete.

Next steps:
  1. Rebuild the kernel, e.g.:
       ./scripts/release/compile_and_package.sh $KERNEL_NAME --localversion <your-tag>
     The $MODULE_NAME.ko module will be produced by the in-tree build and
     end up in the generated Debian package at:
       /lib/modules/<version>/kernel/drivers/staging/$DRIVER_DIRNAME/$MODULE_NAME.ko

  2. If you build a full rootfs via
       scripts/flash/rootfs_prep/helpers/build_third_party_drivers.sh
     or one of the L4T scripts under scripts/rootfs/<bsp>/Linux_for_Tegra/,
     remove "$DRIVER" from THIRD_PARTY_DRIVERS so the driver isn't built
     twice. The flash/rootfs_prep variant in this repo has already been
     updated.
EOF
