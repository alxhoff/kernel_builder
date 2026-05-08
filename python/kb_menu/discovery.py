from __future__ import annotations

from pathlib import Path


def list_kernel_trees(repo_root: Path) -> list[str]:
    kd = repo_root / "storage" / "kernels"
    out: list[str] = []
    if not kd.is_dir():
        return out
    for d in sorted(kd.iterdir()):
        if d.name == ".gitkeep" or not d.is_dir():
            continue
        if (d / "kernel" / "kernel").is_dir():
            out.append(d.name)
    return out


def list_extracted_bsps(repo_root: Path) -> list[str]:
    bsp = repo_root / "scripts" / "flash" / "rootfs_prep" / "bsp"
    out: list[str] = []
    if not bsp.is_dir():
        return out
    for d in sorted(bsp.iterdir()):
        if not d.is_dir():
            continue
        l4t = d / "Linux_for_Tegra"
        if (l4t / "rootfs").is_dir():
            out.append(d.name)
    return out
