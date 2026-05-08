"""Textual kb-menu application (menuconfig-style)."""

from __future__ import annotations

import os
import shutil
from pathlib import Path

from textual.app import App
from textual.binding import Binding

from kb_menu.config import (
    adv,
    config_path,
    load_config,
    log_path,
    normalize_arch_tag,
    save_config,
    set_adv,
)
from kb_menu.dialogs import (
    ChecklistModal,
    ConfirmModal,
    InfoModal,
    InputModal,
    RadiolistModal,
    SelectModal,
)
from kb_menu.runner import RunModal
from kb_menu.screens import MenuEntry, MenuHubScreen


class KbMenuApp(App[None]):
    """Root application: repo cwd, persisted cfg, dialog + run helpers."""

    BINDINGS = [
        Binding("q", "quit", "Quit", show=True),
    ]

    CSS = """
    #nav-hint {
        height: auto;
        padding: 0 1;
        color: $foreground 70%;
        text-style: dim;
    }
    /* Remaining width + min-width so help text wraps and never collapses to zero. */
    #help-scroll {
        width: 1fr;
        min-width: 22;
        height: 100%;
        border: tall $primary;
        padding: 0 1;
    }
    #help-panel {
        width: 100%;
        height: auto;
    }
    #menu-list {
        width: 45%;
        min-width: 0;
        height: 100%;
        border: tall $accent;
    }
    /* Long text in info / confirm modals */
    .info-scroll, .confirm-body {
        width: 100%;
        min-width: 0;
        max-height: 85%;
        height: auto;
    }
    .info-scroll Static, .confirm-body Static {
        width: 100%;
    }
    #menu-row {
        height: 1fr;
        min-height: 0;
    }
    Horizontal.buttons {
        height: auto;
        min-height: 0;
        margin-top: 1;
    }
    /* Centered stack for modal pickers */
    RadiolistModal,
    SelectModal,
    ChecklistModal,
    InputModal,
    ConfirmModal,
    InfoModal {
        align: center middle;
    }
    .kb-dialog {
        width: 90%;
        max-width: 100;
        height: auto;
        max-height: 90%;
        background: $surface;
        border: thick $primary;
        padding: 1 2;
    }
    .kb-dialog OptionList#choices {
        height: auto;
        max-height: 18;
        min-height: 3;
        border: tall $border;
    }
    .dialog-hint {
        color: $foreground 60%;
        text-style: dim;
        height: auto;
        margin-bottom: 1;
    }
    """

    def __init__(self) -> None:
        super().__init__()
        self.repo_root = Path(__file__).resolve().parents[2]
        self.menu_config_path = config_path(self.repo_root)
        self.menu_log_path = log_path(self.repo_root)
        self.cfg = load_config(self.menu_config_path, self.repo_root)
        os.chdir(self.repo_root)

    def on_mount(self) -> None:
        from kb_menu import workflows as wf

        self.push_screen(
            MenuHubScreen(
                "kb-menu",
                "Cartken kernel + Jetson bring-up — pick an area; highlight a row for full help on the right",
                [
                    MenuEntry(
                        "bsp",
                        "Jetson BSP & rootfs (L4T on disk)",
                        (
                            "Everything that prepares NVIDIA L4T under bsp/ and shapes a rootfs for "
                            "a robot before imaging.\n\n"
                            "• Prepare — download/extract L4T, apply Cartken GitLab tag, drivers, "
                            "optional kernel/display/chroot (setup_tegra_package.sh).\n"
                            "• Customize rootfs — take an existing BSP tree and add cart<robot> "
                            "identity, certs, env, optional tag pull (setup_rootfs_as_robot_for_"
                            "flashing.sh). Not the same as compiling a kernel in storage/kernels/.\n"
                            "• Full pipeline — both steps in order.\n\n"
                            "Open this submenu for longer explanations per action."
                        ),
                        wf.open_bsp_menu,
                    ),
                    MenuEntry(
                        "kernel",
                        "Kernel trees (storage/kernels)",
                        (
                            "Work on standalone kernel checkouts: compile, build .deb packages, "
                            "modules-only builds, Kconfig editors, clean/mrproper, Docker image "
                            "management, and in-BSP rebuild via Linux_for_Tegra. This is the "
                            "day-to-day kernel development path separate from flashing rootfs."
                        ),
                        wf.open_kernel_menu,
                    ),
                    MenuEntry(
                        "releases",
                        "Kernel tags & releases (kernel_tags)",
                        (
                            "Release engineering: list/show tags, export manifest, create or delete "
                            "tags, promote lifecycle status, diff releases, verify on hardware, "
                            "deploy .deb. Requires jq. Uses scripts/release/kernel_tags.sh and "
                            "related storage for manifests and archives."
                        ),
                        wf.open_releases_menu,
                    ),
                    MenuEntry(
                        "ota",
                        "OTA updates",
                        (
                            "Build full OTA payloads and prepare rootfs trees for over-the-air "
                            "delivery (scripts/ota/*). Different entry points and flags from USB "
                            "flash rootfs prep in BSP."
                        ),
                        wf.open_ota_menu,
                    ),
                    MenuEntry(
                        "device",
                        "Running device (SSH)",
                        (
                            "Post-install maintenance on a live Jetson: bootloader update, UEFI "
                            "update, EKB .deb workflow. Assumes network access and credentials; "
                            "does not replace mass-flash or recovery."
                        ),
                        wf.open_device_menu,
                    ),
                    MenuEntry(
                        "workspace",
                        "Workspace & inspection",
                        (
                            "Read-only / diagnostic helpers: list BSP folders under bsp/, enter a "
                            "rootfs with jetson_chroot.sh, read the last command log from kb-menu "
                            "runs (.kb-menu.last.log)."
                        ),
                        wf.open_workspace_menu,
                    ),
                    MenuEntry(
                        "settings",
                        "Saved defaults",
                        (
                            "Edit scripts/menu/.kb-menu.config (JetPack, SoC, token, toolchain, "
                            "kernel tree name, DTB defaults, …). Wizards pre-fill from these "
                            "values so you are not retyping toolchains and tags every time."
                        ),
                        wf.open_settings_menu,
                    ),
                ],
            )
        )

    async def action_quit(self) -> None:
        self.exit()

    def persist(self) -> None:
        save_config(self.menu_config_path, self.cfg)

    async def dlg_confirm(self, title: str, body: str) -> bool:
        return await self.push_screen_wait(ConfirmModal(title, body))

    async def dlg_info(self, text: str) -> None:
        await self.push_screen_wait(InfoModal(text))

    async def dlg_input(
        self, label: str, default: str = "", password: bool = False
    ) -> str | None:
        return await self.push_screen_wait(InputModal(label, default, password))

    async def dlg_select(
        self,
        title: str,
        choices: list[tuple[str, str]],
        default_key: str | None,
    ) -> str | None:
        return await self.push_screen_wait(SelectModal(title, choices, default_key))

    async def dlg_radio(self, title: str, keys: list[str], default_key: str) -> str | None:
        return await self.push_screen_wait(RadiolistModal(title, keys, default_key))

    async def dlg_checklist(
        self, title: str, items: list[tuple[str, str, bool]]
    ) -> list[str] | None:
        return await self.push_screen_wait(ChecklistModal(title, items))

    async def run_cmd(self, argv: list[str]) -> int:
        return await self.push_screen_wait(
            RunModal(argv, self.repo_root, self.menu_log_path)
        )

    # --- shared picks -------------------------------------------------
    async def pick_jetpack(self) -> str | None:
        keys = ["5.1.2", "5.1.3", "5.1.4", "5.1.5", "6.0DP", "6.1", "6.2"]
        return await self.dlg_radio("JetPack version", keys, self.cfg.get("JETPACK", "5.1.5"))

    async def pick_soc(self) -> str | None:
        return await self.dlg_radio("SoC", ["orin", "xavier"], self.cfg.get("SOC", "orin"))

    async def pick_env(self) -> str | None:
        return await self.dlg_radio(
            "Backend env", ["production", "staging", "sandbox"], self.cfg.get("ENV", "production")
        )

    async def pick_arch(self) -> str | None:
        cur = normalize_arch_tag(self.cfg.get("COMPILE_ARCH", "arm64"))
        return await self.dlg_radio("Target architecture (--arch)", ["arm64", "x86_64", "arm"], cur)

    async def pick_kernel_tree(self) -> str | None:
        from kb_menu.discovery import list_kernel_trees

        trees = list_kernel_trees(self.repo_root)
        if not trees:
            return await self.dlg_input(
                "Kernel tree name (storage/kernels/)", self.cfg.get("KERNEL_NAME", "")
            )
        cur = self.cfg.get("KERNEL_NAME", "")
        if cur not in trees:
            cur = trees[0]
        return await self.dlg_radio("Kernel source (storage/kernels/)", trees, cur)

    async def pick_bsp(self) -> str | None:
        from kb_menu.discovery import list_extracted_bsps

        bsps = list_extracted_bsps(self.repo_root)
        if not bsps:
            return await self.dlg_input(
                "Target BSP (no extracted BSPs under bsp/)", self.cfg.get("JETPACK", "5.1.5")
            )
        cur = self.cfg.get("JETPACK", "5.1.5")
        if cur not in bsps:
            cur = bsps[0]
        return await self.dlg_radio("Target BSP (from bsp/)", bsps, cur)

    async def ensure_access_token(self) -> bool:
        if self.cfg.get("ACCESS_TOKEN"):
            r = await self.dlg_select(
                "GitLab access token",
                [
                    ("reuse", "Use saved token"),
                    ("replace", "Enter a new token"),
                    ("clear", "Forget token (prompt next time)"),
                ],
                "reuse",
            )
            if r is None:
                return False
            if r == "reuse":
                return True
            if r == "clear":
                self.cfg["ACCESS_TOKEN"] = ""
                self.persist()
                return await self.ensure_access_token()
            t = await self.dlg_input("New token (saved chmod 600)", "", password=True)
            if not t:
                return False
            self.cfg["ACCESS_TOKEN"] = t
            self.persist()
            return True
        t = await self.dlg_input(
            "GitLab access token (saved to .kb-menu.config)", "", password=True
        )
        if not t:
            return False
        self.cfg["ACCESS_TOKEN"] = t
        self.persist()
        return True

    def toolchain_from_config(self) -> tuple[str, str] | None:
        """Saved cross-compile prefix + version (no UI)."""
        n = (self.cfg.get("PACKAGE_TOOLCHAIN_NAME") or "").strip()
        v = (self.cfg.get("PACKAGE_TOOLCHAIN_VERSION") or "").strip()
        if not n or not v:
            return None
        return n, v

    def toolchain_gcc_path(self, name: str, version: str) -> Path:
        """Where kernel_builder expects the cross-gcc (matches CROSS_COMPILE prefix)."""
        return (
            self.repo_root
            / "storage"
            / "toolchains"
            / name
            / version
            / "bin"
            / f"{name}-gcc"
        )

    async def require_toolchain(self) -> tuple[str, str] | None:
        """Use saved toolchain for builds; Settings if unset; verify clone on disk."""
        t = self.toolchain_from_config()
        if not t:
            await self.dlg_info(
                "Toolchain name and version are not both set.\n\n"
                "Open Settings → Toolchain (compile & package) and save them once; "
                "build flows will reuse those values."
            )
            return None
        gcc = self.toolchain_gcc_path(t[0], t[1])
        if not gcc.is_file():
            await self.dlg_info(
                f"Cross-compiler not found on disk:\n{gcc}\n\n"
                "From the repo root, clone the toolchain (example for Jetson / buildroot 9.3):\n"
                "python3 python/kernel_builder.py clone-toolchain \\\n"
                "  --toolchain-url https://github.com/alxhoff/Jetson-Linux-Toolchain \\\n"
                "  --toolchain-name aarch64-buildroot-linux-gnu \\\n"
                "  --toolchain-version 9.3\n\n"
                "If your tree uses another triplet, Settings → Toolchain must match the "
                "prefix of the binaries under storage/toolchains/<name>/<version>/bin/.\n\n"
                "After a failed run, see also: scripts/menu/.kb-menu.last.log"
            )
            return None
        return t

    async def edit_toolchain_defaults(self) -> None:
        """Settings: edit PACKAGE_TOOLCHAIN_* and persist."""
        n = await self.dlg_input("--toolchain-name", self.cfg.get("PACKAGE_TOOLCHAIN_NAME", ""))
        if n is None:
            return
        v = await self.dlg_input("--toolchain-version", self.cfg.get("PACKAGE_TOOLCHAIN_VERSION", ""))
        if v is None:
            return
        self.cfg["PACKAGE_TOOLCHAIN_NAME"] = n.strip()
        self.cfg["PACKAGE_TOOLCHAIN_VERSION"] = v.strip()
        self.persist()
        gcc = self.toolchain_gcc_path(n.strip(), v.strip())
        if not gcc.is_file():
            await self.dlg_info(
                f"Saved. Cross-compiler is still missing:\n{gcc}\n\n"
                "Run clone-toolchain from the repo root (see Settings help text) or fix name/version."
            )

    async def form_advanced_bsp_setup(self) -> bool:
        items = [
            ("ADV_NO_DOWNLOAD", "--no-download", adv(self.cfg, "ADV_NO_DOWNLOAD")),
            ("ADV_JUST_CLONE", "--just-clone", adv(self.cfg, "ADV_JUST_CLONE")),
            ("ADV_SKIP_KERNEL_BUILD", "--skip-kernel-build", adv(self.cfg, "ADV_SKIP_KERNEL_BUILD")),
            (
                "ADV_SKIP_DISPLAY_DRIVER_BUILD",
                "--skip-display-driver-build",
                adv(self.cfg, "ADV_SKIP_DISPLAY_DRIVER_BUILD"),
            ),
            ("ADV_SKIP_PINMUX", "--skip-pinmux", adv(self.cfg, "ADV_SKIP_PINMUX")),
            ("ADV_SKIP_CHROOT_BUILD", "--skip-chroot-build", adv(self.cfg, "ADV_SKIP_CHROOT_BUILD")),
            ("ADV_PROMPT", "--prompt", adv(self.cfg, "ADV_PROMPT")),
            ("ADV_REBUILD", "--rebuild (docker)", adv(self.cfg, "ADV_REBUILD")),
            ("ADV_INSPECT", "--inspect (docker)", adv(self.cfg, "ADV_INSPECT")),
        ]
        sel = await self.dlg_checklist("Advanced: setup_tegra_package", items)
        if sel is None:
            return False
        for k, _, _ in items:
            set_adv(self.cfg, k, k in sel)
        return True

    async def form_advanced_flash(self) -> bool:
        items = [
            ("ADV_SKIP_VPN", "--skip-vpn", adv(self.cfg, "ADV_SKIP_VPN")),
            ("ADV_SKIP_SSH_CA", "--skip-ssh-ca", adv(self.cfg, "ADV_SKIP_SSH_CA")),
            ("ADV_CLEAN_ROOTFS", "--clean-rootfs", adv(self.cfg, "ADV_CLEAN_ROOTFS")),
            ("ADV_DRY_RUN", "--dry-run", adv(self.cfg, "ADV_DRY_RUN")),
        ]
        sel = await self.dlg_checklist("Advanced: robot flash", items)
        if sel is None:
            return False
        for k, _, _ in items:
            set_adv(self.cfg, k, k in sel)
        return True


def main() -> None:
    if not shutil.which("bash"):
        raise SystemExit("kb-menu: bash is required.")
    KbMenuApp().run()
