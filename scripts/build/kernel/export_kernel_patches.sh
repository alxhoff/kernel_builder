#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Export cartken kernel git commits as patches for BSP builds.

Patches are generated with git format-patch from the tagged import base
through HEAD, and written to sources/patches/<jetpack-version>/.

Usage:
  export_kernel_patches.sh [KERNEL_NAME] [JETPACK_VERSION]

Examples:
  export_kernel_patches.sh cartken_7_2 7.2
  export_kernel_patches.sh cartken_6_2 6.2

Workflow:
  1. Make changes in storage/kernels/<KERNEL_NAME>/
  2. Commit each logical change separately
  3. Run this script to refresh sources/patches/<version>/

The initial stock import commit is tagged patch-base and is not exported.
EOF
}

KERNEL_NAME="${1:-}"
JP_VERSION="${2:-}"

if [[ -z "$KERNEL_NAME" || -z "$JP_VERSION" ]]; then
    usage
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(realpath "$SCRIPT_DIR/../../..")"
KERNEL_TREE="$REPO_ROOT/storage/kernels/$KERNEL_NAME"
PATCH_DIR="$REPO_ROOT/sources/patches/$JP_VERSION"
BASE_TAG="patch-base"

if [[ ! -d "$KERNEL_TREE/.git" ]]; then
    echo "Error: $KERNEL_TREE is not a git repository." >&2
    exit 1
fi

if ! git -C "$KERNEL_TREE" rev-parse --verify "$BASE_TAG" >/dev/null 2>&1; then
    root_commit="$(git -C "$KERNEL_TREE" rev-list --max-parents=0 HEAD)"
    echo "Tagging $BASE_TAG at root commit ${root_commit:0:12}..."
    git -C "$KERNEL_TREE" tag -f "$BASE_TAG" "$root_commit"
fi

base_commit="$(git -C "$KERNEL_TREE" rev-parse "$BASE_TAG")"
patch_count="$(git -C "$KERNEL_TREE" rev-list --count "${base_commit}..HEAD" 2>/dev/null || echo 0)"

mkdir -p "$PATCH_DIR"

find "$PATCH_DIR" -maxdepth 1 -name '*.patch' -delete

if [[ "$patch_count" -eq 0 ]]; then
    echo "No commits after $BASE_TAG in $KERNEL_NAME; removed stale patches from $PATCH_DIR"
else
    git -C "$KERNEL_TREE" format-patch -o "$PATCH_DIR" "${base_commit}..HEAD" >/dev/null
    echo "Exported $patch_count patch(es) from $KERNEL_NAME to $PATCH_DIR"
    git -C "$KERNEL_TREE" log --oneline "${base_commit}..HEAD"
fi

base_subject="$(git -C "$KERNEL_TREE" log -1 --format='%s' "$base_commit")"
cat > "$PATCH_DIR/BASE_COMMIT" <<EOF
# Stock kernel import — not applied as a patch during BSP builds.
commit: $base_commit
tag: $BASE_TAG
subject: $base_subject
date: $(git -C "$KERNEL_TREE" log -1 --format='%ai' "$base_commit")
kernel_tree: storage/kernels/$KERNEL_NAME
EOF
