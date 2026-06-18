"""Helpers for detecting and building Jetson nvbuild kernel trees (JP6/JP7)."""

from __future__ import annotations

import os
import subprocess


def kernel_tree_root(kernel_name: str) -> str:
    return os.path.join("storage", "kernels", kernel_name)


def is_nvbuild_kernel(kernel_name: str) -> bool:
    return os.path.isfile(os.path.join(kernel_tree_root(kernel_name), "nvbuild.sh"))


def nvbuild_kernel_src_subdir(kernel_name: str) -> str | None:
    kernel_parent = os.path.join(kernel_tree_root(kernel_name), "kernel")
    if not os.path.isdir(kernel_parent):
        return None
    for name in ("kernel-noble", "kernel-jammy-src", "kernel"):
        path = os.path.join(kernel_parent, name)
        if os.path.isdir(path):
            return name
    return None


def nvbuild_kernel_src_dir(kernel_name: str) -> str | None:
    subdir = nvbuild_kernel_src_subdir(kernel_name)
    if not subdir:
        return None
    return os.path.join(kernel_tree_root(kernel_name), "kernel", subdir)


def nvbuild_kernel_out_dir(kernel_name: str) -> str:
    return os.path.join(kernel_tree_root(kernel_name), "kernel_out")


def nvbuild_image_path(kernel_name: str) -> str:
    subdir = nvbuild_kernel_src_subdir(kernel_name) or "kernel-noble"
    return os.path.join(
        nvbuild_kernel_out_dir(kernel_name),
        "kernel",
        subdir,
        "arch",
        "arm64",
        "boot",
        "Image",
    )


def normalize_localversion_suffix(localversion) -> str:
    if not localversion:
        return ""
    value = str(localversion)
    return value if value.startswith("-") else f"-{value}"


def nvbuild_out_config_path(kernel_name: str) -> str | None:
    subdir = nvbuild_kernel_src_subdir(kernel_name)
    if not subdir:
        return None
    return os.path.join(nvbuild_kernel_out_dir(kernel_name), "kernel", subdir, ".config")


def nvbuild_incremental_ready(kernel_name: str) -> bool:
    path = nvbuild_out_config_path(kernel_name)
    return path is not None and os.path.isfile(path)


def nvbuild_incremental_build_commands(
    arch: str,
    threads: int | None,
    *,
    oot_only: bool = False,
) -> list[str]:
    """Shell commands for an incremental JP6/JP7 nvbuild (cwd = kernel tree root).

    Syncs sources into kernel_out without rsync --delete, keeps .config and object
    files, runs olddefconfig instead of defconfig, then rebuilds only what changed.
    """
    jobs = str(threads) if threads else "$(nproc)"
    parts = [
        "set -e",
        'source "./kernel_src_build_env.sh"',
        'KERNEL_OUT="${KERNEL_OUT_DIR:-$PWD/kernel_out}"',
        'OUT_SRC="$KERNEL_OUT/kernel/${KERNEL_SRC_DIR}"',
        'if [[ ! -f "$OUT_SRC/.config" ]]; then echo "Error: incremental build needs kernel_out/.config; run with --no-incremental or --clean first." >&2; exit 1; fi',
        'mkdir -p "$KERNEL_OUT/kernel"',
        'echo "==> Incremental sync (preserving build artifacts)"',
        'rsync -a "kernel/${KERNEL_SRC_DIR}/" "$OUT_SRC/"',
        'cp -a kernel/Makefile "$KERNEL_OUT/kernel/"',
        "for item in ${OOT_SOURCE_LIST}; do rsync -aR \"$item\" \"$KERNEL_OUT/\"; done",
        'cp -a Makefile "$KERNEL_OUT/"',
        'export KERNEL_HEADERS="$OUT_SRC"',
    ]
    if not oot_only:
        parts += [
            'echo "==> Incremental in-tree kernel (reuse .config + Image + modules)"',
            # CROSS_COMPILE MUST be passed to olddefconfig: Kconfig evaluates
            # compiler-gated symbols (e.g. CC_HAVE_STACKPROTECTOR_SYSREG, which
            # selects CONFIG_STACKPROTECTOR_PER_TASK on arm64) with $(CC). Without
            # the cross prefix, $(CC) falls back to the host x86 gcc, which rejects
            # -mstack-protector-guard=sysreg and silently drops PER_TASK. That
            # desyncs the config from a vmlinux built per-task and makes OOT modpost
            # fail with "__stack_chk_guard undefined". The env exports CROSS_COMPILE
            # (see kernel_builder.py); guard against it being empty just in case.
            'if [[ -z "${CROSS_COMPILE:-}" ]]; then echo "Error: CROSS_COMPILE unset; olddefconfig would mis-detect compiler-gated configs (e.g. STACKPROTECTOR_PER_TASK)." >&2; exit 1; fi',
            # Resolve any NEW Kconfig symbols to their defaults non-interactively
            # (stdin from /dev/null). olddefconfig is idempotent on a complete
            # .config: it rewrites byte-identical content, so kbuild's syncconfig
            # stays a no-op and the build remains incremental. Crucially it also
            # stops `make` from dropping into an interactive oldconfig prompt
            # (which hangs the build) whenever the source tree adds new symbols.
            f'make -j{jobs} ARCH={arch} CROSS_COMPILE="${{CROSS_COMPILE}}" -C "$OUT_SRC" olddefconfig </dev/null',
            f'make -j{jobs} ARCH={arch} CROSS_COMPILE="${{CROSS_COMPILE}}" -C "$OUT_SRC" --output-sync=target Image modules </dev/null',
        ]
    else:
        parts.append('echo "==> Incremental OOT modules only (kernel image unchanged)"')
    parts += [
        'echo "==> Incremental NVIDIA OOT modules + DTBs"',
        f'make -j{jobs} -C "$KERNEL_OUT" kernel_name="${{kernel_name}}" system_type=l4t modules',
        "make -C \"$KERNEL_OUT\" dtbs",
    ]
    return parts


def nvbuild_localversion_export(localversion: str) -> str:
    suffix = normalize_localversion_suffix(localversion)
    if not suffix:
        return ""
    return f'export LOCALVERSION="{suffix}"'


def jp7_toolchain_defaults() -> tuple[str, str]:
    return "aarch64-none-linux-gnu", "13.2"


def cross_compile_prefix(toolchain_name: str, toolchain_version: str, docker: bool = False) -> str:
    if docker:
        if toolchain_name == "aarch64-none-linux-gnu":
            return "/opt/nvidia-l4t-toolchain/x-tools/aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-"
        return (
            f"/builder/toolchains/{toolchain_name}/{toolchain_version}/bin/{toolchain_name}-"
        )
    return (
        f"storage/toolchains/{toolchain_name}/{toolchain_version}/bin/{toolchain_name}-"
    )


def ensure_jp7_toolchain_storage(repo_root: str, dry_run: bool = False) -> None:
    script = os.path.join(
        repo_root, "scripts", "build", "kernel", "ensure_jp7_toolchain_storage.sh"
    )
    if not os.path.isfile(script):
        raise FileNotFoundError(f"Missing JP7 toolchain helper: {script}")
    if dry_run:
        print(f"[Dry-run] Would run: {script}")
        return
    subprocess.run(["bash", script], cwd=repo_root, check=True)


def locate_nvbuild_dtb(kernel_name: str, dtb_name: str) -> str | None:
    root = kernel_tree_root(kernel_name)
    search_roots = [
        os.path.join(root, "kernel_out"),
        root,
    ]
    for search_root in search_roots:
        if not os.path.isdir(search_root):
            continue
        find_command = f"find {search_root} -name {dtb_name}"
        try:
            find_output = subprocess.check_output(
                find_command, shell=True, universal_newlines=True
            ).strip()
            if find_output:
                return find_output.splitlines()[0]
        except subprocess.CalledProcessError:
            continue
    return None
