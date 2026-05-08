"""Persisted menu defaults — same keys as legacy bash kb-menu (KB_MENU_* file)."""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

DEFAULTS: dict[str, str] = {
    "JETPACK": "5.1.5",
    "SOC": "orin",
    "TAG": "",
    "ACCESS_TOKEN": "",
    "ROBOT_NUMBER": "",
    "ENV": "production",
    "HOST_CERT_VALIDITY": "48h",
    "DOCKER": "0",
    "BASE_JETPACK": "5.1.5",
    "TARGET_JETPACK": "5.1.5",
    "LOCALVERSION": "-cartken5.1.5",
    "ADV_NO_DOWNLOAD": "0",
    "ADV_JUST_CLONE": "0",
    "ADV_SKIP_KERNEL_BUILD": "0",
    "ADV_SKIP_DISPLAY_DRIVER_BUILD": "0",
    "ADV_SKIP_PINMUX": "0",
    "ADV_SKIP_CHROOT_BUILD": "0",
    "ADV_PROMPT": "0",
    "ADV_REBUILD": "0",
    "ADV_INSPECT": "0",
    "ADV_SKIP_VPN": "0",
    "ADV_SKIP_SSH_CA": "0",
    "ADV_CLEAN_ROOTFS": "0",
    "ADV_DRY_RUN": "0",
    "KERNEL_NAME": "cartken_5_1_5",
    "PACKAGE_CONFIG": "",
    "PACKAGE_THREADS": "",
    "PACKAGE_TOOLCHAIN_NAME": "aarch64-buildroot-linux-gnu",
    "PACKAGE_TOOLCHAIN_VERSION": "9.3",
    "PACKAGE_TAG": "",
    "PACKAGE_DESCRIPTION": "",
    "PACKAGE_TAG_STATUS": "development",
    "PACKAGE_DTB_NAME": "",
    "PACKAGE_OVERLAYS": "",
    "ADV_PKG_DRY_RUN": "0",
    "ADV_PKG_BUILD_DTB": "0",
    "ADV_PKG_BUILD_MODULES": "0",
    "COMPILE_ARCH": "arm64",
    "COMPILE_BUILD_TARGET": "",
    "COMPILE_DTB_NAME": "tegra234-p3701-0000-p3737-0000.dtb",
    "COMPILE_THREADS": "",
    "COMPILE_CONFIG": "",
    "COMPILE_OVERLAYS": "",
    "ADV_COMPILE_HOST_BUILD": "0",
    "ADV_COMPILE_CLEAN": "0",
    "ADV_COMPILE_USE_CURRENT_CONFIG": "0",
    "ADV_COMPILE_GENERATE_CTAGS": "0",
    "ADV_COMPILE_BUILD_DTB": "0",
    "ADV_COMPILE_BUILD_MODULES": "0",
    "ADV_COMPILE_DRY_RUN": "0",
    "ADV_DOCKER_REBUILD": "0",
    "KT_TAG_NAME": "",
    "KT_LOG_LIMIT": "20",
    "KT_EXPORT_FORMAT": "json",
    "KT_EXPORT_STATUS_FILTER": "",
    "KT_DEPLOY_REMOTE_DIR": "~/kernel_debs",
    "KT_LIST_STATUS_FILTER": "any",
    "ADV_KT_NO_SOURCE_TAG": "0",
    "ADV_KT_NO_ARCHIVE": "0",
    "ADV_KT_NO_PUBLISH": "0",
    "ADV_KT_FORCE": "0",
}


def normalize_arch_tag(value: str) -> str:
    a = (value or "").lower()
    if a in ("arm64", "aarch64"):
        return "arm64"
    if a in ("x86_64", "amd64"):
        return "x86_64"
    if a in ("arm", "arm32", "armhf"):
        return "arm"
    return "arm64"


def config_path(repo_root: Path) -> Path:
    return repo_root / "scripts" / "menu" / ".kb-menu.config"


def log_path(repo_root: Path) -> Path:
    return repo_root / "scripts" / "menu" / ".kb-menu.last.log"


def load_config(path: Path, repo_root: Path) -> dict[str, str]:
    cfg = dict(DEFAULTS)
    if not path.is_file():
        cfg["COMPILE_ARCH"] = normalize_arch_tag(cfg["COMPILE_ARCH"])
        return cfg
    # Load KB_MENU_* via bash `source` so we match legacy %q escaping.
    py = shlex.quote(sys.executable)
    inner = (
        "import json,os; "
        'print(json.dumps({k[8:]:v for k,v in os.environ.items() if k.startswith("KB_MENU_")}))'
    )
    script = (
        "set -a; "
        f"source {shlex.quote(str(path))} 2>/dev/null || true; "
        f"set +a; {py} -c {shlex.quote(inner)}"
    )
    try:
        r = subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            cwd=str(repo_root),
            timeout=30,
        )
        if r.returncode == 0 and r.stdout.strip():
            loaded = json.loads(r.stdout)
            for k, v in loaded.items():
                cfg[k] = str(v) if v is not None else ""
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
        pass
    cfg["COMPILE_ARCH"] = normalize_arch_tag(cfg.get("COMPILE_ARCH", "arm64"))
    return cfg


def save_config(path: Path, cfg: dict[str, str]) -> None:
    lines = [
        "# kb-menu persistence file (auto-generated)\n",
        "# Keys are KB_MENU_* (bash-compatible). May contain secrets; chmod 600.\n",
    ]
    for key in sorted(cfg.keys()):
        val = str(cfg.get(key, ""))
        lines.append(f"KB_MENU_{key}={shlex.quote(val)}\n")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(lines), encoding="utf-8")
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


def mask_token(t: str) -> str:
    if not t:
        return "(empty)"
    n = len(t)
    if n <= 8:
        return "*" * n
    return f"{t[:6]}{'*' * max(0, n - 10)}{t[-4:]}"


def adv(cfg: dict[str, str], key: str) -> bool:
    return cfg.get(key, "0") == "1"


def set_adv(cfg: dict[str, str], key: str, on: bool) -> None:
    cfg[key] = "1" if on else "0"
