"""All menu actions (ported from kb-menu-legacy.sh)."""

from __future__ import annotations

import shutil
from pathlib import Path
from typing import Any

from kb_menu.config import adv, normalize_arch_tag, set_adv

# --- navigation hubs -----------------------------------------------------


async def open_bsp_menu(app: Any) -> None:
    from kb_menu.screens import MenuEntry, MenuHubScreen

    app.push_screen(
        MenuHubScreen(
            "Jetson BSP & rootfs",
            "L4T / Linux_for_Tegra under bsp/ — separate from kernel trees in storage/kernels/",
            [
                MenuEntry(
                    "prepare",
                    "Prepare L4T BSP (download, extract, Cartken layers)",
                    (
                        "WHAT IT DOES\n"
                        "Runs scripts/flash/rootfs_prep/setup_tegra_package.sh (sudo). "
                        "It fetches and unpacks the NVIDIA Jetson Linux (L4T) BSP for your JetPack "
                        "version, applies Cartken-specific layers (drivers, pinmux, display stack, "
                        "etc.) from GitLab using the tag you choose, and can build kernel/display "
                        "pieces inside that BSP tree unless you skip them in Advanced.\n\n"
                        "WHEN TO USE IT\n"
                        "First time or when you need a fresh bsp/<version>/Linux_for_Tegra tree "
                        "before customizing a rootfs. This step does not push an image to a robot; "
                        "it prepares the source tree on disk.\n\n"
                        "INPUTS\n"
                        "JetPack version, SoC (orin/xavier), GitLab tag, access token, native vs "
                        "Docker, plus Advanced flags (no-download, skip kernel build, chroot, …).\n\n"
                        "OUTPUT\n"
                        "Populated BSP layout under bsp/ suitable for the next step (robot rootfs "
                        "customization) or for manual flashing workflows."
                    ),
                    build_bsp,
                ),
                MenuEntry(
                    "flash",
                    "Customize rootfs for a robot (pre-flash)",
                    (
                        "WHAT IT DOES\n"
                        "Runs scripts/flash/rootfs_prep/setup_rootfs_as_robot_for_flashing.sh (sudo). "
                        "You select an already-extracted BSP (folder under bsp/) as --target-bsp. "
                        "The script layers robot identity onto that rootfs: robot number "
                        "(cart<N>), environment (production/staging/sandbox), host/SSH CA material "
                        "with a validity window, optional VPN/CA steps, packages, and optional "
                        "pull of a fresh GitLab tag into the tree.\n\n"
                        "WHEN TO USE IT\n"
                        "After Prepare (or if you already have a BSP tree). Use this when you want "
                        "a rootfs ready to flash or image for a specific robot role—not when you "
                        "only want to compile a kernel from storage/kernels/.\n\n"
                        "INPUTS\n"
                        "Target BSP folder, SoC, robot number, env, cert validity, whether to pull a "
                        "new tag (needs token), Advanced (skip VPN, skip SSH CA, clean rootfs, "
                        "dry-run).\n\n"
                        "NOTE\n"
                        "Name says 'flashing' because it prepares the image you will flash; the "
                        "script itself runs on your host and modifies the rootfs tree."
                    ),
                    flash_robot,
                ),
                MenuEntry(
                    "both",
                    "Full pipeline: prepare BSP, then customize rootfs",
                    (
                        "WHAT IT DOES\n"
                        "Runs the Prepare wizard to completion, then asks whether to run the "
                        "Customize rootfs for a robot wizard immediately afterward.\n\n"
                        "WHEN TO USE IT\n"
                        "End-to-end: from 'get L4T + Cartken BSP on disk' through 'this rootfs is "
                        "configured for cart robot N'. Step 2 still shows its own prompts (target "
                        "BSP, robot number, etc.) so you can align them with what Prepare just "
                        "produced.\n\n"
                        "WHEN NOT TO USE IT\n"
                        "If you only need to refresh the BSP, use Prepare alone. If the BSP is "
                        "already prepared and you only need another robot configuration, use "
                        "Customize rootfs alone."
                    ),
                    build_and_flash,
                ),
            ],
        )
    )


async def open_kernel_menu(app: Any) -> None:
    from kb_menu.screens import MenuEntry, MenuHubScreen

    app.push_screen(
        MenuHubScreen(
            "Kernel (storage/kernels)",
            "Out-of-tree kernels under storage/kernels/<name>/ — not the L4T BSP kernel unless you point there",
            [
                MenuEntry(
                    "compile",
                    "Compile kernel & modules (no .deb)",
                    (
                        "Runs python/kernel_builder.py compile (Docker by default, or host with "
                        "--host-build in Advanced). Produces Image, modules tree, optional DTB "
                        "copy under the kernel tree—no Debian package.\n\n"
                        "Wizard covers tree, arch, localversion, config, build targets, threads, "
                        "DTB/overlays from saved defaults, toolchain from Settings, and advanced "
                        "flags (clean, dry-run, build-dtb, …)."
                    ),
                    kernel_compile,
                ),
                MenuEntry(
                    "package",
                    "Build & package as .deb",
                    (
                        "Runs scripts/release/compile_and_package.sh (same idea as bin/package): "
                        "compile then wrap the result as an installable .deb, with optional "
                        "kernel_tags metadata (--tag, description, status).\n\n"
                        "Use when you need a releasable package, not just a build tree."
                    ),
                    kernel_package,
                ),
                MenuEntry(
                    "modules",
                    "Modules only (faster incremental)",
                    (
                        "Shortcut to kernel_builder.py with --build-target modules: rebuild kernel "
                        "modules and modules_install layout only. Useful after source changes when "
                        "you do not need a full Image rebuild."
                    ),
                    kernel_modules_only,
                ),
                MenuEntry(
                    "kconfig",
                    "Kernel configuration UIs",
                    (
                        "Runs scripts/build/kernel/* for menuconfig, nconfig, xconfig, or "
                        "savedefconfig against the selected storage/kernels tree. Uses your "
                        "saved toolchain. xconfig needs DISPLAY."
                    ),
                    kernel_kconfig,
                ),
                MenuEntry(
                    "clean",
                    "make clean (keep .config)",
                    (
                        "Runs clean_kernel.sh → kernel_builder compile --build-target clean. "
                        "Removes most build products but keeps configuration; lighter than mrproper."
                    ),
                    kernel_clean,
                ),
                MenuEntry(
                    "mrproper",
                    "make mrproper (full tree reset)",
                    (
                        "Runs mrproper_kernel.sh — wipes the kernel build tree including .config. "
                        "Use when you need a pristine tree; you will need to re-run defconfig/"
                        "oldconfig afterward."
                    ),
                    kernel_mrproper,
                ),
                MenuEntry(
                    "docker",
                    "kernel_builder Docker image",
                    (
                        "Manage the kernel_builder container image: build, rebuild, inspect, or "
                        "cleanup. Default compiles use this image unless you pass --host-build."
                    ),
                    kernel_docker,
                ),
                MenuEntry(
                    "rebuild",
                    "Rebuild inside BSP Linux_for_Tegra",
                    (
                        "Uses NVIDIA's build_kernel.sh under an extracted BSP (bsp/…/Linux_for_"
                        "Tegra). This is the in-BSP kernel workflow, not storage/kernels. Pick "
                        "BSP and options when prompted."
                    ),
                    kernel_rebuild_bsp,
                ),
            ],
        )
    )


async def open_ota_menu(app: Any) -> None:
    from kb_menu.screens import MenuEntry, MenuHubScreen

    app.push_screen(
        MenuHubScreen(
            "OTA",
            "Artifacts for over-the-air updates (separate from USB flash rootfs prep)",
            [
                MenuEntry(
                    "payload",
                    "Build full OTA update payload",
                    (
                        "Runs scripts/ota/create_full_ota_update.sh. Bundles what the OTA pipeline "
                        "expects (images, metadata, etc.) for a given robot/tag/BSP base. "
                        "Confirm robots, JetPack, tag, and advanced VPN/dry-run options in the wizard."
                    ),
                    ota_payload,
                ),
                MenuEntry(
                    "rootfs",
                    "Prepare rootfs for OTA (not USB flash)",
                    (
                        "Runs scripts/ota/setup_rootfs_as_robot_for_ota.sh. Similar spirit to the "
                        "flash-prep script but tuned for OTA delivery: robot number, SoC, tag, "
                        "target/base BSP, optional skip flags. Use when your update path is OTA, "
                        "not raw flash."
                    ),
                    ota_rootfs,
                ),
            ],
        )
    )


async def open_device_menu(app: Any) -> None:
    from kb_menu.screens import MenuEntry, MenuHubScreen

    app.push_screen(
        MenuHubScreen(
            "Running device",
            "Deploy to a live Jetson over SSH (assumes reachability and sudo where scripts require it)",
            [
                MenuEntry(
                    "bootloader",
                    "Update bootloader / flash partitions",
                    (
                        "Runs scripts/deploy/update_bootloader.sh against a host you specify. "
                        "Used when you need to refresh bootloader-related components without a "
                        "full reflash; follow on-device prompts and script safety checks."
                    ),
                    deploy_bootloader,
                ),
                MenuEntry(
                    "uefi",
                    "Update UEFI firmware",
                    (
                        "Runs scripts/deploy/update_uefi.sh. Pushes UEFI payloads appropriate to "
                        "your BSP/device; confirm target IP/credentials in the flow."
                    ),
                    deploy_uefi,
                ),
                MenuEntry(
                    "ekb",
                    "EKB / encryption-bypass package (.deb)",
                    (
                        "Runs scripts/deploy/create_ekb_update.sh to build or stage an EKB .deb "
                        "for devices that use NVIDIA's encrypted-boot workflow. Not every robot "
                        "needs this—use when your security model calls for EKB updates."
                    ),
                    deploy_ekb,
                ),
            ],
        )
    )


async def open_workspace_menu(app: Any) -> None:
    from kb_menu.screens import MenuEntry, MenuHubScreen

    app.push_screen(
        MenuHubScreen(
            "Workspace",
            "Inspect repo state, enter a rootfs chroot, read logs — no flashing",
            [
                MenuEntry(
                    "bsps",
                    "List extracted BSPs",
                    (
                        "Shows which JetPack/BSP directories exist under bsp/ (output of Prepare "
                        "or manual extracts). Use to pick a sensible --target-bsp before flash or "
                        "OTA scripts."
                    ),
                    util_list_bsps,
                ),
                MenuEntry(
                    "chroot",
                    "Enter rootfs with jetson_chroot.sh",
                    (
                        "Runs scripts/utils/chroot/jetson_chroot.sh with a Linux_for_Tegra/rootfs "
                        "path and SoC. Drops you into a shell inside the image for package tweaks, "
                        "inspection, or debugging. Requires sudo."
                    ),
                    util_chroot,
                ),
                MenuEntry(
                    "log",
                    "View last kb-menu command log",
                    (
                        "Opens scripts/menu/.kb-menu.last.log — stdout/stderr from the most recent "
                        "Run modal. Use when you need to copy errors or review a long build."
                    ),
                    util_view_log,
                ),
            ],
        )
    )


async def open_settings_menu(app: Any) -> None:
    from kb_menu.screens import MenuEntry, MenuHubScreen

    c = app.cfg
    app.push_screen(
        MenuHubScreen(
            "Settings",
            "Saved defaults written to scripts/menu/.kb-menu.config (KB_MENU_*); wizards pre-fill from here",
            [
                MenuEntry(
                    "jp",
                    f"JetPack default ({c.get('JETPACK')})",
                    (
                        "Default JetPack version string used when a wizard asks for JetPack (BSP "
                        "prepare, paths under bsp/). Must match folders you actually maintain."
                    ),
                    settings_jetpack,
                ),
                MenuEntry(
                    "soc",
                    f"SoC ({c.get('SOC')})",
                    (
                        "orin or xavier — drives chroot, some deploy scripts, and BSP-related "
                        "prompts. Wrong SoC can break pinmux or rootfs assumptions."
                    ),
                    settings_soc,
                ),
                MenuEntry(
                    "env",
                    f"Env ({c.get('ENV')})",
                    (
                        "production | staging | sandbox — default environment label for robot "
                        "rootfs customization (flash/OTA) and related tooling."
                    ),
                    settings_env,
                ),
                MenuEntry(
                    "tag",
                    f"Tag ({c.get('TAG') or 'unset'})",
                    (
                        "Default GitLab tag for Cartken layers (BSP prepare, optional tag pull "
                        "during flash). Not the same as kernel_tags release names unless you align them."
                    ),
                    settings_tag,
                ),
                MenuEntry(
                    "token",
                    "GitLab access token",
                    (
                        "Private token for GitLab APIs/repos used by BSP prepare and tag-pull flows. "
                        "Stored in .kb-menu.config; treat the file as secret."
                    ),
                    settings_token,
                ),
                MenuEntry(
                    "robot",
                    f"Robot # ({c.get('ROBOT_NUMBER') or 'unset'})",
                    (
                        "Default robot index for cart<N> identity in rootfs scripts (you can "
                        "override per run in the wizard)."
                    ),
                    settings_robot,
                ),
                MenuEntry(
                    "validity",
                    f"Cert validity ({c.get('HOST_CERT_VALIDITY')})",
                    (
                        "Default validity window for host/SSH CA material (e.g. 48h, 7d) when "
                        "configuring a robot rootfs."
                    ),
                    settings_validity,
                ),
                MenuEntry(
                    "localver",
                    f"localversion ({c.get('LOCALVERSION')})",
                    (
                        "Default kernel LOCALVERSION suffix (often with a leading dash in config). "
                        "Used as starting value in compile/package/tag wizards."
                    ),
                    settings_localver,
                ),
                MenuEntry(
                    "kname",
                    f"Kernel tree ({c.get('KERNEL_NAME')})",
                    (
                        "Default name under storage/kernels/<name> for compile/package workflows."
                    ),
                    settings_kname,
                ),
                MenuEntry(
                    "arch",
                    f"Compile arch ({c.get('COMPILE_ARCH')})",
                    (
                        "Default ARCH for kernel_builder (arm64, x86_64, arm). Normalized on load."
                    ),
                    settings_arch,
                ),
                MenuEntry(
                    "toolchain",
                    f"Toolchain ({c.get('PACKAGE_TOOLCHAIN_NAME')} / {c.get('PACKAGE_TOOLCHAIN_VERSION')})",
                    (
                        "Cross-compile triplet and version folder under storage/toolchains/<name>/"
                        "<version>/bin/. Used for all compile, package, Kconfig, clean, mrproper "
                        "flows—set once, rarely changed."
                    ),
                    settings_toolchain,
                ),
                MenuEntry(
                    "pkgcfg",
                    f"Package config ({c.get('PACKAGE_CONFIG') or 'empty'})",
                    (
                        "Default make target/config for compile_and_package (e.g. defconfig name). "
                        "Empty means let the script/kernel tree default apply."
                    ),
                    settings_pkgcfg,
                ),
                MenuEntry(
                    "ccfg",
                    f"Compile config ({c.get('COMPILE_CONFIG') or 'empty'})",
                    (
                        "Default kernel_builder --config argument (e.g. tegra_defconfig). Empty "
                        "omits explicit config step in the wizard default."
                    ),
                    settings_ccfg,
                ),
                MenuEntry(
                    "dtbc",
                    f"Compile DTB ({c.get('COMPILE_DTB_NAME') or 'empty'})",
                    (
                        "Default DTB filename for compile and kernel_tags tag create. Empty skips "
                        "--dtb-name. Change when your board uses a different blob."
                    ),
                    settings_compile_dtb,
                ),
                MenuEntry(
                    "dtbp",
                    f"Package DTB ({c.get('PACKAGE_DTB_NAME') or 'empty'})",
                    (
                        "Default DTB for compile_and_package / bin/package only; can differ from "
                        "compile DTB if packaging another variant."
                    ),
                    settings_package_dtb,
                ),
                MenuEntry(
                    "clear",
                    "Reset all saved values",
                    (
                        "Deletes .kb-menu.config and exits kb-menu. Next launch recreates defaults. "
                        "Use when you want a clean slate (tokens, toolchains, DTB defaults all reset)."
                    ),
                    settings_clear,
                ),
            ],
        )
    )


async def open_releases_menu(app: Any) -> None:
    if not shutil.which("jq"):
        await app.dlg_info("kernel_tags.sh requires jq.\n  pacman -S jq   or   apt install jq")
        return
    from kb_menu.screens import MenuEntry, MenuHubScreen

    app.push_screen(
        MenuHubScreen(
            "Kernel releases & tags",
            "kernel_tags.sh — versioned kernel .deb releases, manifest JSON, production_kernels (needs jq)",
            [
                MenuEntry(
                    "list",
                    "List tags",
                    (
                        "Lists release tags from the manifest with optional status filters. Use to "
                        "see what has been built, promoted, or archived without opening JSON by hand."
                    ),
                    kt_list,
                ),
                MenuEntry(
                    "show",
                    "Show one tag",
                    (
                        "Prints the full JSON record for a single tag: kernel name, localversion, "
                        "paths, status, notes—useful for debugging or CI inspection."
                    ),
                    kt_show,
                ),
                MenuEntry(
                    "log",
                    "Build / release log",
                    (
                        "Shows the chronological kernel_tags log (who built what, when). Handy after "
                        "a long compile/package pipeline."
                    ),
                    kt_log,
                ),
                MenuEntry(
                    "kernels",
                    "Kernel trees status",
                    (
                        "Summarizes storage/kernels trees vs what the manifest knows—helps spot "
                        "untracked trees or missing checkouts."
                    ),
                    kt_kernels,
                ),
                MenuEntry(
                    "get-deb",
                    "Resolve archived .deb path",
                    (
                        "Looks up the stored path or artifact location for a tagged .deb (get-deb). "
                        "Use before scp or install."
                    ),
                    kt_get_deb,
                ),
                MenuEntry(
                    "export",
                    "Export manifest",
                    (
                        "Dumps manifest data as JSON or text for backups, diffs, or external "
                        "dashboards. Optional status filter."
                    ),
                    kt_export,
                ),
                MenuEntry(
                    "tag",
                    "Create new release tag",
                    (
                        "Creates a manifest entry: archives metadata, optional GitLab publish, "
                        "optional production_kernels registration. This is the 'release this build' "
                        "action after you have a .deb."
                    ),
                    kt_tag_create,
                ),
                MenuEntry(
                    "promote",
                    "Promote tag status",
                    (
                        "Moves a tag along the development → testing → staging → production "
                        "lifecycle (or your configured states). Use for release discipline."
                    ),
                    kt_promote,
                ),
                MenuEntry(
                    "notes",
                    "Append note to tag",
                    (
                        "Adds a human-readable note to a tag record (incident, QA result, customer). "
                        "Does not change binaries."
                    ),
                    kt_notes,
                ),
                MenuEntry(
                    "diff",
                    "Diff two tags",
                    (
                        "Compares two manifest entries—kernel versions, configs, artifact hashes—"
                        "to see what changed between releases."
                    ),
                    kt_diff,
                ),
                MenuEntry(
                    "verify",
                    "Verify installed kernel on device",
                    (
                        "SSH to a robot and checks running kernel/modules against what the tag "
                        "expects. Use after deploy to confirm the right .deb landed."
                    ),
                    kt_verify,
                ),
                MenuEntry(
                    "deploy",
                    "Deploy .deb to robot(s)",
                    (
                        "Copies or installs the tagged .deb to one or more hosts via the deploy "
                        "helpers (paths/SSH from wizard). Not the same as OTA full payload."
                    ),
                    kt_deploy,
                ),
                MenuEntry(
                    "delete",
                    "Delete tag",
                    (
                        "Removes a tag from the manifest and associated archive metadata. "
                        "Destructive—use when a release was created by mistake."
                    ),
                    kt_delete,
                ),
                MenuEntry(
                    "paths",
                    "Where artifacts live",
                    (
                        "Explains filesystem layout for manifest JSON, archives, and related "
                        "paths so you can find files outside kb-menu."
                    ),
                    kt_paths_help,
                ),
            ],
        )
    )


# --- BSP -----------------------------------------------------------------

rp = lambda app: app.repo_root
ROOTFS = lambda app: rp(app) / "scripts" / "flash" / "rootfs_prep"
OTA = lambda app: rp(app) / "scripts" / "ota"
DEPLOY = lambda app: rp(app) / "scripts" / "deploy"
BUILDK = lambda app: rp(app) / "scripts" / "build" / "kernel"
KTAGS = lambda app: rp(app) / "scripts" / "release" / "kernel_tags.sh"
PYKB = lambda app: rp(app) / "python" / "kernel_builder.py"


async def build_bsp(app: Any) -> None:
    jp = await app.pick_jetpack()
    if jp is None:
        return
    soc = await app.pick_soc()
    if soc is None:
        return
    tag = await app.dlg_input("GitLab tag (e.g. v7.5.0-sshca8)", app.cfg.get("TAG", ""))
    if not tag:
        await app.dlg_info("Tag is required for setup_tegra_package.sh.")
        return
    mode = await app.dlg_select(
        "Run mode",
        [("Native", "Native (no Docker)"), ("Docker", "Docker")],
        "Docker" if app.cfg.get("DOCKER") == "1" else "Native",
    )
    if mode is None:
        return
    app.cfg["DOCKER"] = "1" if mode == "Docker" else "0"
    if not await app.ensure_access_token():
        return
    if not await app.form_advanced_bsp_setup():
        return
    app.cfg["JETPACK"], app.cfg["SOC"], app.cfg["TAG"] = jp, soc, tag
    app.persist()
    cmd = [
        "sudo",
        str(ROOTFS(app) / "setup_tegra_package.sh"),
        "--jetpack",
        jp,
        "--soc",
        soc,
        "--access-token",
        app.cfg["ACCESS_TOKEN"],
        "--tag",
        tag,
    ]
    if app.cfg["DOCKER"] == "1":
        cmd.append("--docker")
    for flag, key in [
        ("--no-download", "ADV_NO_DOWNLOAD"),
        ("--just-clone", "ADV_JUST_CLONE"),
        ("--skip-kernel-build", "ADV_SKIP_KERNEL_BUILD"),
        ("--skip-display-driver-build", "ADV_SKIP_DISPLAY_DRIVER_BUILD"),
        ("--skip-pinmux", "ADV_SKIP_PINMUX"),
        ("--skip-chroot-build", "ADV_SKIP_CHROOT_BUILD"),
        ("--prompt", "ADV_PROMPT"),
    ]:
        if adv(app.cfg, key):
            cmd.append(flag)
    if adv(app.cfg, "ADV_REBUILD") and app.cfg["DOCKER"] == "1":
        cmd.append("--rebuild")
    if adv(app.cfg, "ADV_INSPECT") and app.cfg["DOCKER"] == "1":
        cmd.append("--inspect")
    body = f"jetpack={jp} soc={soc} tag={tag} mode={mode}"
    if await app.dlg_confirm("BSP: prepare rootfs", body):
        await app.run_cmd(cmd)


async def flash_robot(app: Any) -> None:
    target = await app.pick_bsp()
    if target is None:
        return
    soc = await app.pick_soc()
    if soc is None:
        return
    robot = await app.dlg_input("Robot number", app.cfg.get("ROBOT_NUMBER", ""))
    if not robot:
        await app.dlg_info("Robot number is required.")
        return
    env = await app.pick_env()
    if env is None:
        return
    validity = await app.dlg_input("Host cert validity (e.g. 48h, 7d)", app.cfg.get("HOST_CERT_VALIDITY", "48h"))
    if validity is None:
        return
    pull = await app.dlg_confirm("Pull", "Pull a fresh cartken --tag during flash?")
    tag = ""
    if pull:
        tag = await app.dlg_input("GitLab tag", app.cfg.get("TAG", ""))
        if tag is None:
            return
        if not await app.ensure_access_token():
            return
    if not await app.form_advanced_flash():
        return
    app.cfg["JETPACK"] = target
    app.cfg["SOC"] = soc
    app.cfg["ROBOT_NUMBER"] = robot
    app.cfg["ENV"] = env
    app.cfg["HOST_CERT_VALIDITY"] = validity
    if tag:
        app.cfg["TAG"] = tag
    app.persist()
    cmd = [
        "sudo",
        str(ROOTFS(app) / "setup_rootfs_as_robot_for_flashing.sh"),
        "--target-bsp",
        target,
        "--soc",
        soc,
        "--robot-number",
        robot,
        "--env",
        env,
        "--host-cert-validity",
        validity,
    ]
    if pull and tag:
        cmd += ["--tag", tag, "--access-token", app.cfg["ACCESS_TOKEN"]]
    if adv(app.cfg, "ADV_SKIP_VPN"):
        cmd.append("--skip-vpn")
    if adv(app.cfg, "ADV_SKIP_SSH_CA"):
        cmd.append("--skip-ssh-ca")
    if adv(app.cfg, "ADV_CLEAN_ROOTFS"):
        cmd.append("--clean-rootfs")
    if adv(app.cfg, "ADV_DRY_RUN"):
        cmd.append("--dry-run")
    if await app.dlg_confirm("BSP: robot flash rootfs", f"target-bsp={target} robot=cart{robot}"):
        await app.run_cmd(cmd)


async def build_and_flash(app: Any) -> None:
    await app.dlg_info(
        "Full BSP pipeline (two wizards)\n\n"
        "1) Prepare L4T BSP — downloads/extracts L4T, applies Cartken GitLab tag, "
        "optional kernel/display/chroot steps. Produces/updates bsp/<jetpack>/…\n\n"
        "2) Customize rootfs for a robot — picks that BSP as target-bsp, sets robot "
        "number, env, certs, optional tag pull. Prepares the rootfs tree for imaging/"
        "flashing.\n\n"
        "You will confirm step 2 separately; you can cancel there if you only needed "
        "Prepare."
    )
    await build_bsp(app)
    if not await app.dlg_confirm("Step 2", "Run robot flash rootfs now?"):
        return
    await flash_robot(app)


# --- OTA -----------------------------------------------------------------


async def ota_payload(app: Any) -> None:
    tag = await app.dlg_input("GitLab tag", app.cfg.get("TAG", ""))
    if not tag:
        await app.dlg_info("Tag is required.")
        return
    base = await app.dlg_input("Base JetPack", app.cfg.get("BASE_JETPACK", "5.1.5"))
    if base is None:
        return
    target = await app.dlg_input("Target JetPack", app.cfg.get("TARGET_JETPACK", "5.1.5"))
    if target is None:
        return
    if not await app.ensure_access_token():
        return
    dr = await app.dlg_checklist("Options", [("ADV_DRY_RUN", "--dry-run", adv(app.cfg, "ADV_DRY_RUN"))])
    if dr is None:
        return
    set_adv(app.cfg, "ADV_DRY_RUN", "ADV_DRY_RUN" in dr)
    app.cfg["TAG"], app.cfg["BASE_JETPACK"], app.cfg["TARGET_JETPACK"] = tag, base, target
    app.persist()
    cmd = [
        "sudo",
        str(OTA(app) / "create_full_ota_update.sh"),
        "--access-token",
        app.cfg["ACCESS_TOKEN"],
        "--tag",
        tag,
        "--base-jetpack",
        base,
        "--target-jetpack",
        target,
    ]
    if adv(app.cfg, "ADV_DRY_RUN"):
        cmd.append("--dry-run")
    if await app.dlg_confirm("OTA payload", f"tag={tag} {base}→{target}"):
        await app.run_cmd(cmd)


async def ota_rootfs(app: Any) -> None:
    robot = await app.dlg_input("Robot number", app.cfg.get("ROBOT_NUMBER", ""))
    if not robot:
        await app.dlg_info("Robot number is required.")
        return
    soc = await app.pick_soc()
    if soc is None:
        return
    tag = await app.dlg_input("GitLab tag", app.cfg.get("TAG", ""))
    if tag is None:
        return
    target = await app.dlg_input("Target BSP", app.cfg.get("TARGET_JETPACK", "5.1.5"))
    if target is None:
        return
    base = await app.dlg_input("Base BSP", app.cfg.get("BASE_JETPACK", "5.1.5"))
    if base is None:
        return
    sel = await app.dlg_checklist(
        "Options",
        [
            ("ADV_SKIP_VPN", "--skip-vpn", adv(app.cfg, "ADV_SKIP_VPN")),
            ("ADV_DRY_RUN", "--dry-run", adv(app.cfg, "ADV_DRY_RUN")),
        ],
    )
    if sel is None:
        return
    set_adv(app.cfg, "ADV_SKIP_VPN", "ADV_SKIP_VPN" in sel)
    set_adv(app.cfg, "ADV_DRY_RUN", "ADV_DRY_RUN" in sel)
    app.cfg.update(
        {"ROBOT_NUMBER": robot, "SOC": soc, "TAG": tag, "TARGET_JETPACK": target, "BASE_JETPACK": base}
    )
    app.persist()
    cmd = [
        "sudo",
        str(OTA(app) / "setup_rootfs_as_robot_for_ota.sh"),
        "--robot-number",
        robot,
        "--soc",
        soc,
        "--tag",
        tag,
        "--target-bsp",
        target,
        "--base-bsp",
        base,
    ]
    if adv(app.cfg, "ADV_SKIP_VPN"):
        cmd.append("--skip-vpn")
    if adv(app.cfg, "ADV_DRY_RUN"):
        cmd.append("--dry-run")
    if await app.dlg_confirm("OTA rootfs", f"robot=cart{robot}"):
        await app.run_cmd(cmd)


# --- kernel --------------------------------------------------------------


async def _pick_localversion_optional(app: Any) -> str | None:
    """None=cancel wizard, ''=omit."""
    r = await app.dlg_select(
        "--localversion (optional)",
        [
            ("skip", "Omit (no --localversion)"),
            ("set", "Enter a suffix…"),
            ("back", "Exit compile wizard"),
        ],
        "skip",
    )
    if r is None or r == "back":
        return None
    if r == "skip":
        return ""
    v = await app.dlg_input(
        "Suffix (no leading -). Empty OK to omit.",
        app.cfg.get("LOCALVERSION", "").lstrip("-"),
    )
    if v is None:
        return None
    return v.lstrip("-")


async def _pick_build_target(app: Any) -> str | None:
    r = await app.dlg_select(
        "--build-target",
        [
            ("def", "Default (full compile path)"),
            ("kernel", "kernel"),
            ("modules", "modules"),
            ("dtbs", "dtbs"),
            ("kdm", "kernel,dtbs,modules"),
            ("bindeb", "bindeb-pkg"),
            ("custom", "Custom…"),
            ("back", "Cancel"),
        ],
        "def",
    )
    if r is None or r == "back":
        return None
    if r == "custom":
        c = await app.dlg_input("Comma-separated targets", app.cfg.get("COMPILE_BUILD_TARGET", ""))
        return c
    if r == "def":
        return ""
    mapping = {"kernel": "kernel", "modules": "modules", "dtbs": "dtbs", "kdm": "kernel,dtbs,modules", "bindeb": "bindeb-pkg"}
    return mapping.get(r, "")


async def kernel_compile(app: Any) -> None:
    kname = await app.pick_kernel_tree()
    if not kname:
        return
    arch = await app.pick_arch()
    if arch is None:
        return
    lv = await _pick_localversion_optional(app)
    if lv is None:
        return
    cfg_c = await app.dlg_input("--config (empty omit)", app.cfg.get("COMPILE_CONFIG", ""))
    if cfg_c is None:
        return
    bt = await _pick_build_target(app)
    if bt is None:
        return
    threads = await app.dlg_input("--threads (empty=all cores)", app.cfg.get("COMPILE_THREADS", ""))
    if threads is None:
        return
    dtb = (app.cfg.get("COMPILE_DTB_NAME") or "").strip()
    ov = await app.dlg_input("--overlays (empty omit)", app.cfg.get("COMPILE_OVERLAYS", ""))
    if ov is None:
        return
    tc = await app.require_toolchain()
    if tc is None:
        return
    items = [
        ("ADV_COMPILE_HOST_BUILD", "--host-build", adv(app.cfg, "ADV_COMPILE_HOST_BUILD")),
        ("ADV_COMPILE_CLEAN", "--clean", adv(app.cfg, "ADV_COMPILE_CLEAN")),
        ("ADV_COMPILE_USE_CURRENT_CONFIG", "--use-current-config", adv(app.cfg, "ADV_COMPILE_USE_CURRENT_CONFIG")),
        ("ADV_COMPILE_GENERATE_CTAGS", "--generate-ctags", adv(app.cfg, "ADV_COMPILE_GENERATE_CTAGS")),
        ("ADV_COMPILE_BUILD_DTB", "--build-dtb", adv(app.cfg, "ADV_COMPILE_BUILD_DTB")),
        ("ADV_COMPILE_BUILD_MODULES", "--build-modules", adv(app.cfg, "ADV_COMPILE_BUILD_MODULES")),
        ("ADV_COMPILE_DRY_RUN", "--dry-run", adv(app.cfg, "ADV_COMPILE_DRY_RUN")),
    ]
    sel = await app.dlg_checklist("Advanced: compile", items)
    if sel is None:
        return
    for k, _, _ in items:
        set_adv(app.cfg, k, k in sel)
    app.cfg["KERNEL_NAME"] = kname
    app.cfg["COMPILE_ARCH"] = arch
    app.cfg["COMPILE_CONFIG"] = cfg_c
    app.cfg["COMPILE_BUILD_TARGET"] = bt
    app.cfg["COMPILE_THREADS"] = threads
    app.cfg["COMPILE_OVERLAYS"] = ov
    if lv:
        app.cfg["LOCALVERSION"] = lv if lv.startswith("-") else f"-{lv}"
    app.persist()
    cmd = [
        "python3",
        str(PYKB(app)),
        "compile",
        "--kernel-name",
        kname,
        "--arch",
        arch,
        "--toolchain-name",
        tc[0],
        "--toolchain-version",
        tc[1],
    ]
    if cfg_c:
        cmd += ["--config", cfg_c]
    if lv:
        cmd += ["--localversion", lv]
    if threads:
        cmd += ["--threads", threads]
    if bt:
        cmd += ["--build-target", bt]
    if dtb:
        cmd += ["--dtb-name", dtb]
    if ov:
        cmd += ["--overlays", ov]
    if adv(app.cfg, "ADV_COMPILE_HOST_BUILD"):
        cmd.append("--host-build")
    if adv(app.cfg, "ADV_COMPILE_CLEAN"):
        cmd.append("--clean")
    if adv(app.cfg, "ADV_COMPILE_USE_CURRENT_CONFIG"):
        cmd.append("--use-current-config")
    if adv(app.cfg, "ADV_COMPILE_GENERATE_CTAGS"):
        cmd.append("--generate-ctags")
    if adv(app.cfg, "ADV_COMPILE_BUILD_DTB"):
        cmd.append("--build-dtb")
    if adv(app.cfg, "ADV_COMPILE_BUILD_MODULES"):
        cmd.append("--build-modules")
    if adv(app.cfg, "ADV_COMPILE_DRY_RUN"):
        cmd.append("--dry-run")
    if await app.dlg_confirm("Kernel: compile", f"{kname} arch={arch}"):
        await app.run_cmd(cmd)


async def kernel_package(app: Any) -> None:
    kname = await app.pick_kernel_tree()
    if not kname:
        return
    lv = await app.dlg_input("--localversion (required)", app.cfg.get("LOCALVERSION", "").lstrip("-"))
    if not lv:
        await app.dlg_info("--localversion is required.")
        return
    config = await app.dlg_input("--config (empty omit)", app.cfg.get("PACKAGE_CONFIG", ""))
    if config is None:
        return
    threads = await app.dlg_input("Compile threads (empty default)", app.cfg.get("PACKAGE_THREADS", ""))
    if threads is None:
        return
    tc = await app.require_toolchain()
    if tc is None:
        return
    dtb = (app.cfg.get("PACKAGE_DTB_NAME") or "").strip()
    overlays = await app.dlg_input("Optional --overlays", app.cfg.get("PACKAGE_OVERLAYS", ""))
    if overlays is None:
        return
    sel = await app.dlg_checklist(
        "Advanced: package",
        [
            ("ADV_PKG_DRY_RUN", "--dry-run", adv(app.cfg, "ADV_PKG_DRY_RUN")),
            ("ADV_PKG_BUILD_DTB", "--build-dtb", adv(app.cfg, "ADV_PKG_BUILD_DTB")),
            ("ADV_PKG_BUILD_MODULES", "--build-modules", adv(app.cfg, "ADV_PKG_BUILD_MODULES")),
        ],
    )
    if sel is None:
        return
    for k, _, _ in [
        ("ADV_PKG_DRY_RUN", "", False),
        ("ADV_PKG_BUILD_DTB", "", False),
        ("ADV_PKG_BUILD_MODULES", "", False),
    ]:
        set_adv(app.cfg, k, k in sel)
    tag = await app.dlg_input("Optional --tag", app.cfg.get("PACKAGE_TAG", ""))
    if tag is None:
        return
    desc = await app.dlg_input("Optional --description", app.cfg.get("PACKAGE_DESCRIPTION", ""))
    if desc is None:
        return
    tag_status = await app.dlg_input("Optional --tag-status", app.cfg.get("PACKAGE_TAG_STATUS", "development"))
    if tag_status is None:
        return
    app.cfg.update(
        {
            "KERNEL_NAME": kname,
            "LOCALVERSION": lv if lv.startswith("-") else f"-{lv}",
            "PACKAGE_CONFIG": config,
            "PACKAGE_THREADS": threads,
            "PACKAGE_OVERLAYS": overlays,
            "PACKAGE_TAG": tag,
            "PACKAGE_DESCRIPTION": desc,
            "PACKAGE_TAG_STATUS": tag_status,
        }
    )
    app.persist()
    cmd = [
        str(rp(app) / "scripts" / "release" / "compile_and_package.sh"),
        kname,
        "--localversion",
        lv,
        "--toolchain-name",
        tc[0],
        "--toolchain-version",
        tc[1],
    ]
    if config:
        cmd += ["--config", config]
    if threads:
        cmd += ["--threads", threads]
    if dtb:
        cmd += ["--dtb-name", dtb]
    if overlays:
        cmd += ["--overlays", overlays]
    if adv(app.cfg, "ADV_PKG_DRY_RUN"):
        cmd.append("--dry-run")
    if adv(app.cfg, "ADV_PKG_BUILD_DTB"):
        cmd.append("--build-dtb")
    if adv(app.cfg, "ADV_PKG_BUILD_MODULES"):
        cmd.append("--build-modules")
    if tag:
        cmd += ["--tag", tag]
        if desc:
            cmd += ["--description", desc]
        if tag_status:
            cmd += ["--tag-status", tag_status]
    if await app.dlg_confirm("Kernel: package", kname):
        await app.run_cmd(cmd)


async def kernel_modules_only(app: Any) -> None:
    kname = await app.pick_kernel_tree()
    if not kname:
        return
    arch = await app.pick_arch()
    if arch is None:
        return
    tc = await app.require_toolchain()
    if tc is None:
        return
    lv = await _pick_localversion_optional(app)
    if lv is None:
        return
    config = await app.dlg_input("--config (empty omit)", app.cfg.get("COMPILE_CONFIG", ""))
    if config is None:
        return
    threads = await app.dlg_input("--threads (empty omit)", app.cfg.get("COMPILE_THREADS", ""))
    if threads is None:
        return
    sel = await app.dlg_checklist(
        "Advanced",
        [
            ("ADV_COMPILE_HOST_BUILD", "--host-build", adv(app.cfg, "ADV_COMPILE_HOST_BUILD")),
            ("ADV_COMPILE_DRY_RUN", "--dry-run", adv(app.cfg, "ADV_COMPILE_DRY_RUN")),
        ],
    )
    if sel is None:
        return
    set_adv(app.cfg, "ADV_COMPILE_HOST_BUILD", "ADV_COMPILE_HOST_BUILD" in sel)
    set_adv(app.cfg, "ADV_COMPILE_DRY_RUN", "ADV_COMPILE_DRY_RUN" in sel)
    app.cfg["KERNEL_NAME"] = kname
    app.cfg["COMPILE_ARCH"] = arch
    if lv:
        app.cfg["LOCALVERSION"] = lv if lv.startswith("-") else f"-{lv}"
    app.persist()
    cmd = [
        "python3",
        str(PYKB(app)),
        "compile",
        "--kernel-name",
        kname,
        "--arch",
        arch,
        "--toolchain-name",
        tc[0],
        "--toolchain-version",
        tc[1],
        "--build-target",
        "modules",
    ]
    if config:
        cmd += ["--config", config]
    if lv:
        cmd += ["--localversion", lv]
    if threads:
        cmd += ["--threads", threads]
    if adv(app.cfg, "ADV_COMPILE_HOST_BUILD"):
        cmd.append("--host-build")
    if adv(app.cfg, "ADV_COMPILE_DRY_RUN"):
        cmd.append("--dry-run")
    if await app.dlg_confirm("Kernel: modules only", kname):
        await app.run_cmd(cmd)


async def kernel_kconfig(app: Any) -> None:
    ui = await app.dlg_select(
        "Kconfig UI",
        [
            ("menuconfig", "menuconfig"),
            ("nconfig", "nconfig"),
            ("xconfig", "xconfig (needs DISPLAY)"),
            ("savedef", "savedefconfig"),
            ("back", "Cancel"),
        ],
        "menuconfig",
    )
    if ui is None or ui == "back":
        return
    kname = await app.pick_kernel_tree()
    if not kname:
        return
    tc = await app.require_toolchain()
    if tc is None:
        return
    scripts = {
        "menuconfig": "menuconfig_kernel.sh",
        "nconfig": "nconfig_kernel.sh",
        "xconfig": "xconfig_kernel.sh",
        "savedef": "savedefconfig.sh",
    }
    script = BUILDK(app) / scripts[ui]
    if await app.dlg_confirm("Kconfig", f"{script.name} {kname}"):
        await app.run_cmd(
            [str(script), "--toolchain-name", tc[0], "--toolchain-version", tc[1], kname]
        )


async def kernel_clean(app: Any) -> None:
    kname = await app.pick_kernel_tree()
    if not kname:
        return
    arch = await app.pick_arch()
    if arch is None:
        return
    tc = await app.require_toolchain()
    if tc is None:
        return
    dry = await app.dlg_confirm("Dry-run", "Print commands only?")
    cmd = [
        str(BUILDK(app) / "clean_kernel.sh"),
        "--kernel-name",
        kname,
        "--arch",
        arch,
        "--toolchain-name",
        tc[0],
        "--toolchain-version",
        tc[1],
    ]
    if dry:
        cmd.append("--dry-run")
    if await app.dlg_confirm("make clean", kname):
        await app.run_cmd(cmd)


async def kernel_mrproper(app: Any) -> None:
    kname = await app.pick_kernel_tree()
    if not kname:
        return
    arch = await app.pick_arch()
    if arch is None:
        return
    tc = await app.require_toolchain()
    if tc is None:
        return
    dry = await app.dlg_confirm("Dry-run", "Print commands only?")
    cmd = [
        str(BUILDK(app) / "mrproper_kernel.sh"),
        "--kernel-name",
        kname,
        "--arch",
        arch,
        "--toolchain-name",
        tc[0],
        "--toolchain-version",
        tc[1],
    ]
    if dry:
        cmd.append("--dry-run")
    if await app.dlg_confirm("make mrproper", f"Wipe tree for {kname}?"):
        await app.run_cmd(cmd)


async def kernel_docker(app: Any) -> None:
    d = await app.dlg_select(
        "Docker",
        [
            ("build", "python kernel_builder.py build"),
            ("rebuild", "build --rebuild"),
            ("inspect", "inspect"),
            ("cleanup", "cleanup"),
            ("back", "Cancel"),
        ],
        "build",
    )
    if d is None or d == "back":
        return
    if d == "build":
        if await app.dlg_confirm("Docker", "Build kernel_builder image?"):
            await app.run_cmd(["python3", str(PYKB(app)), "build"])
    elif d == "rebuild":
        if await app.dlg_confirm("Docker", "Rebuild image without cache?"):
            await app.run_cmd(["python3", str(PYKB(app)), "build", "--rebuild"])
    elif d == "inspect":
        await app.run_cmd(["python3", str(PYKB(app)), "inspect"])
    else:
        if await app.dlg_confirm("Docker", "Remove kernel_builder image?"):
            await app.run_cmd(["python3", str(PYKB(app)), "cleanup"])


async def kernel_rebuild_bsp(app: Any) -> None:
    from kb_menu.discovery import list_extracted_bsps

    bsps = list_extracted_bsps(app.repo_root)
    if not bsps:
        await app.dlg_info("No extracted BSPs. Prepare BSP first.")
        return
    cur = app.cfg.get("JETPACK", "")
    if cur not in bsps:
        cur = bsps[0]
    target = await app.dlg_radio("Target BSP", bsps, cur)
    if target is None:
        return
    lv = await app.dlg_input("--localversion", app.cfg.get("LOCALVERSION", ""))
    if lv is None:
        return
    tegra = ROOTFS(app) / "bsp" / target / "Linux_for_Tegra"
    bsh = tegra / "build_kernel.sh"
    if not bsh.is_file():
        await app.dlg_info(f"Missing {bsh}")
        return
    app.cfg["JETPACK"] = target
    app.cfg["LOCALVERSION"] = lv
    app.persist()
    if await app.dlg_confirm("BSP kernel rebuild", str(tegra)):
        await app.run_cmd(["sudo", str(bsh), "--patch", target, "--localversion", lv])


# --- kernel tags ---------------------------------------------------------


async def kt_paths_help(app: Any) -> None:
    rr = rp(app)
    msg = (
        "Tracked manifest + artifacts:\n\n"
        f"  {rr / 'storage' / 'kernel_tags.json'}\n"
        f"  {rr / 'storage' / 'kernel_archive'}/\n"
        f"  {rr / 'storage' / 'production_kernels'}/\n"
        f"  {rr / 'storage' / 'kernel_debs'}/\n\n"
        "CLI: scripts/release/kernel_tags.sh"
    )
    await app.dlg_info(msg)


async def kt_list(app: Any) -> None:
    st = await app.dlg_radio(
        "Status filter",
        ["any", "development", "testing", "staging", "production"],
        app.cfg.get("KT_LIST_STATUS_FILTER", "any"),
    )
    if st is None:
        return
    kernel = await app.dlg_input("Kernel name filter (empty=all)", app.cfg.get("KERNEL_NAME", ""))
    if kernel is None:
        return
    verbose = await app.dlg_confirm("Verbose", "Add --all?")
    app.cfg["KT_LIST_STATUS_FILTER"] = st
    if kernel:
        app.cfg["KERNEL_NAME"] = kernel
    app.persist()
    cmd = [str(KTAGS(app)), "list"]
    if st != "any":
        cmd += ["--status", st]
    if kernel:
        cmd += ["--kernel", kernel]
    if verbose:
        cmd.append("--all")
    if await app.dlg_confirm("kernel_tags list", " ".join(cmd)):
        await app.run_cmd(cmd)


async def kt_show(app: Any) -> None:
    t = await app.dlg_input("Tag name", app.cfg.get("KT_TAG_NAME", ""))
    if not t:
        return
    app.cfg["KT_TAG_NAME"] = t
    app.persist()
    if await app.dlg_confirm("kernel_tags show", t):
        await app.run_cmd([str(KTAGS(app)), "show", t])


async def kt_log(app: Any) -> None:
    lim = await app.dlg_input("Max entries (default 20)", app.cfg.get("KT_LOG_LIMIT", "20"))
    if lim is None:
        return
    app.cfg["KT_LOG_LIMIT"] = lim
    app.persist()
    cmd = [str(KTAGS(app)), "log"]
    if lim:
        cmd += ["--limit", lim]
    if await app.dlg_confirm("kernel_tags log", " ".join(cmd)):
        await app.run_cmd(cmd)


async def kt_kernels(app: Any) -> None:
    if await app.dlg_confirm("kernel_tags kernels", "List kernel trees?"):
        await app.run_cmd([str(KTAGS(app)), "kernels"])


async def kt_get_deb(app: Any) -> None:
    t = await app.dlg_input("Tag name", app.cfg.get("KT_TAG_NAME", ""))
    if not t:
        return
    app.cfg["KT_TAG_NAME"] = t
    app.persist()
    if await app.dlg_confirm("get-deb", t):
        await app.run_cmd([str(KTAGS(app)), "get-deb", t])


async def kt_export(app: Any) -> None:
    fmt = await app.dlg_radio("Format", ["json", "text"], app.cfg.get("KT_EXPORT_FORMAT", "json"))
    if fmt is None:
        return
    st = await app.dlg_radio(
        "Status",
        ["any", "development", "testing", "staging", "production"],
        app.cfg.get("KT_EXPORT_STATUS_FILTER") or "any",
    )
    if st is None:
        return
    out = await app.dlg_input("Output file (empty=stdout)", "")
    if out is None:
        return
    app.cfg["KT_EXPORT_FORMAT"] = fmt
    app.cfg["KT_EXPORT_STATUS_FILTER"] = st
    app.persist()
    cmd = [str(KTAGS(app)), "export", "--format", fmt]
    if st != "any":
        cmd += ["--status", st]
    if out:
        cmd += ["--output", out]
    if await app.dlg_confirm("export", " ".join(cmd)):
        await app.run_cmd(cmd)


async def kt_tag_create(app: Any) -> None:
    tname = await app.dlg_input("New tag name", app.cfg.get("KT_TAG_NAME", ""))
    if not tname:
        return
    kname = await app.pick_kernel_tree()
    if not kname:
        return
    lv = await app.dlg_input("--localversion (required)", app.cfg.get("LOCALVERSION", "").lstrip("-"))
    if not lv:
        await app.dlg_info("localversion required.")
        return
    desc = await app.dlg_input("--description", app.cfg.get("PACKAGE_DESCRIPTION", ""))
    if desc is None:
        return
    cfg = await app.dlg_input("--config (empty omit)", "")
    if cfg is None:
        return
    dtb = (app.cfg.get("COMPILE_DTB_NAME") or "").strip()
    st = await app.dlg_radio(
        "Deployment status",
        ["development", "testing", "staging", "production"],
        app.cfg.get("PACKAGE_TAG_STATUS", "development"),
    )
    if st is None:
        return
    soc = await app.dlg_select(
        "production_kernels --soc",
        [("_none", "omit"), ("orin", "orin"), ("xavier", "xavier")],
        "_none",
    )
    if soc is None:
        return
    debpath = await app.dlg_input("--deb-package (empty auto)", "")
    if debpath is None:
        return
    sel = await app.dlg_checklist(
        "Advanced",
        [
            ("ADV_KT_NO_SOURCE_TAG", "--no-source-tag", adv(app.cfg, "ADV_KT_NO_SOURCE_TAG")),
            ("ADV_KT_NO_ARCHIVE", "--no-archive", adv(app.cfg, "ADV_KT_NO_ARCHIVE")),
            ("ADV_KT_NO_PUBLISH", "--no-publish", adv(app.cfg, "ADV_KT_NO_PUBLISH")),
            ("ADV_KT_FORCE", "--force", adv(app.cfg, "ADV_KT_FORCE")),
        ],
    )
    if sel is None:
        return
    for k in ("ADV_KT_NO_SOURCE_TAG", "ADV_KT_NO_ARCHIVE", "ADV_KT_NO_PUBLISH", "ADV_KT_FORCE"):
        set_adv(app.cfg, k, k in sel)
    app.cfg.update(
        {
            "KT_TAG_NAME": tname,
            "LOCALVERSION": lv if lv.startswith("-") else f"-{lv}",
            "PACKAGE_DESCRIPTION": desc,
            "PACKAGE_TAG_STATUS": st,
        }
    )
    app.persist()
    cmd = [
        str(KTAGS(app)),
        "tag",
        tname,
        "--kernel",
        kname,
        "--localversion",
        lv,
        "--description",
        desc,
        "--status",
        st,
    ]
    if cfg:
        cmd += ["--config", cfg]
    if dtb:
        cmd += ["--dtb-name", dtb]
    if soc != "_none":
        cmd += ["--soc", soc]
    if debpath:
        cmd += ["--deb-package", debpath]
    if adv(app.cfg, "ADV_KT_NO_SOURCE_TAG"):
        cmd.append("--no-source-tag")
    if adv(app.cfg, "ADV_KT_NO_ARCHIVE"):
        cmd.append("--no-archive")
    if adv(app.cfg, "ADV_KT_NO_PUBLISH"):
        cmd.append("--no-publish")
    if adv(app.cfg, "ADV_KT_FORCE"):
        cmd.append("--force")
    if await app.dlg_confirm("kernel_tags tag", f"{tname} (needs jq)"):
        await app.run_cmd(cmd)


async def kt_promote(app: Any) -> None:
    t = await app.dlg_input("Tag name", app.cfg.get("KT_TAG_NAME", ""))
    if not t:
        return
    st = await app.dlg_radio(
        "New status",
        ["development", "testing", "staging", "production"],
        "production",
    )
    if st is None:
        return
    app.cfg["KT_TAG_NAME"] = t
    app.cfg["PACKAGE_TAG_STATUS"] = st
    app.persist()
    if await app.dlg_confirm("promote", f"{t} -> {st}"):
        await app.run_cmd([str(KTAGS(app)), "promote", t, "--status", st])


async def kt_notes(app: Any) -> None:
    t = await app.dlg_input("Tag name", app.cfg.get("KT_TAG_NAME", ""))
    if not t:
        return
    note = await app.dlg_input("Note (--add)", "")
    if not note:
        await app.dlg_info("Note required.")
        return
    app.cfg["KT_TAG_NAME"] = t
    app.persist()
    if await app.dlg_confirm("notes", t):
        await app.run_cmd([str(KTAGS(app)), "notes", t, "--add", note])


async def kt_diff(app: Any) -> None:
    a = await app.dlg_input("First tag", app.cfg.get("KT_TAG_NAME", ""))
    if a is None:
        return
    b = await app.dlg_input("Second tag", "")
    if not a or not b:
        await app.dlg_info("Two tags required.")
        return
    if await app.dlg_confirm("diff", f"{a} vs {b}"):
        await app.run_cmd([str(KTAGS(app)), "diff", a, b])


async def kt_verify(app: Any) -> None:
    t = await app.dlg_input("Tag name", app.cfg.get("KT_TAG_NAME", ""))
    if not t:
        return
    ip = await app.dlg_input("Device IP (empty=config)", "")
    if ip is None:
        return
    user = await app.dlg_input("SSH user (empty=config)", "")
    if user is None:
        return
    app.cfg["KT_TAG_NAME"] = t
    app.persist()
    cmd = [str(KTAGS(app)), "verify", t]
    if ip:
        cmd += ["--ip", ip]
    if user:
        cmd += ["--user", user]
    if await app.dlg_confirm("verify", " ".join(cmd)):
        await app.run_cmd(cmd)


async def kt_deploy(app: Any) -> None:
    t = await app.dlg_input("Tag name", app.cfg.get("KT_TAG_NAME", ""))
    if not t:
        return
    mode = await app.dlg_select(
        "Deploy target",
        [
            ("default", "device_ip from scripts/config"),
            ("ip", "Single --ip"),
            ("fleet", "--robots + prefix"),
            ("hosts", "--hosts-file"),
            ("back", "Cancel"),
        ],
        "default",
    )
    if mode is None or mode == "back":
        return
    user = await app.dlg_input("--user (empty default)", "")
    if user is None:
        return
    rdir = await app.dlg_input("--remote-dir", app.cfg.get("KT_DEPLOY_REMOTE_DIR", "~/kernel_debs"))
    if rdir is None:
        return
    pw = await app.dlg_input("SSH password (empty ok)", "", password=True)
    if pw is None:
        return
    app.cfg["KT_TAG_NAME"] = t
    app.cfg["KT_DEPLOY_REMOTE_DIR"] = rdir
    app.persist()
    cmd = [str(KTAGS(app)), "deploy", t]
    if user:
        cmd += ["--user", user]
    if rdir:
        cmd += ["--remote-dir", rdir]
    if pw:
        cmd += ["--password", pw]
    if mode == "ip":
        ip = await app.dlg_input("Device IP", "")
        if not ip:
            await app.dlg_info("IP required.")
            return
        cmd += ["--ip", ip]
    elif mode == "fleet":
        robots = await app.dlg_input("Robots (1,2,5-8)", app.cfg.get("ROBOT_NUMBER", ""))
        prefix = await app.dlg_input("IP prefix", "10.42.0.")
        if not robots or prefix is None:
            return
        cmd += ["--robots", robots, "--robot-ip-prefix", prefix]
    elif mode == "hosts":
        hf = await app.dlg_input("Hosts file", "")
        if not hf:
            return
        cmd += ["--hosts-file", hf]
    extra = await app.dlg_checklist(
        "Options",
        [
            ("INSTALL", "--install", False),
            ("NOREBOOT", "--no-reboot", False),
            ("SEQUENTIAL", "--sequential", False),
            ("DRYRUN", "--dry-run", False),
        ],
    )
    if extra is None:
        return
    if "INSTALL" in extra:
        cmd.append("--install")
    if "NOREBOOT" in extra:
        cmd.append("--no-reboot")
    if "SEQUENTIAL" in extra:
        cmd.append("--sequential")
    if "DRYRUN" in extra:
        cmd.append("--dry-run")
    if await app.dlg_confirm("deploy", " ".join(cmd)):
        await app.run_cmd(cmd)


async def kt_delete(app: Any) -> None:
    t = await app.dlg_input("Tag to delete", app.cfg.get("KT_TAG_NAME", ""))
    if not t:
        return
    if not await app.dlg_confirm("Delete", f"Remove tag {t} and archive? Cannot undo."):
        return
    if await app.dlg_confirm("Confirm delete", t):
        await app.run_cmd([str(KTAGS(app)), "delete", t])


# --- device deploy -------------------------------------------------------


async def deploy_bootloader(app: Any) -> None:
    target = await app.pick_bsp()
    if target is None:
        return
    ip = await app.dlg_input("Device IP (empty=config)", "")
    if ip is None:
        return
    sel = await app.dlg_checklist(
        "Flags",
        [
            ("FORCE", "--force", False),
            ("CHECK_VAR", "--check-var", False),
            ("SWAP_SLOT", "--swap-slot", False),
            ("BOTH_SLOTS", "--both-slots", False),
            ("BUILD_ONLY", "--build-only", False),
        ],
    )
    if sel is None:
        return
    cmd = ["sudo", str(DEPLOY(app) / "update_bootloader.sh"), "--target-bsp", target]
    if ip:
        cmd += ["--ip", ip]
    if "FORCE" in sel:
        cmd.append("--force")
    if "CHECK_VAR" in sel:
        cmd.append("--check-var")
    if "SWAP_SLOT" in sel:
        cmd.append("--swap-slot")
    if "BOTH_SLOTS" in sel:
        cmd.append("--both-slots")
    if "BUILD_ONLY" in sel:
        cmd.append("--build-only")
    if await app.dlg_confirm("Bootloader", target):
        await app.run_cmd(cmd)


async def deploy_uefi(app: Any) -> None:
    v = await app.dlg_input("--target-version", app.cfg.get("JETPACK", "5.1.5"))
    if v is None:
        return
    if await app.dlg_confirm("UEFI", v):
        await app.run_cmd(["sudo", str(DEPLOY(app) / "update_uefi.sh"), "--target-version", v])


async def deploy_ekb(app: Any) -> None:
    v = await app.dlg_input("--l4t-version", app.cfg.get("JETPACK", "5.1.5"))
    if v is None:
        return
    if await app.dlg_confirm("EKB", v):
        await app.run_cmd(["sudo", str(DEPLOY(app) / "create_ekb_update.sh"), "--l4t-version", v])


# --- workspace -----------------------------------------------------------


async def util_list_bsps(app: Any) -> None:
    from kb_menu.discovery import list_extracted_bsps

    bsps = list_extracted_bsps(app.repo_root)
    if not bsps:
        await app.dlg_info(f"No BSPs under {ROOTFS(app) / 'bsp'}.")
        return
    lines = "\n".join(f"  - {b}  ({ROOTFS(app) / 'bsp' / b / 'Linux_for_Tegra'})" for b in bsps)
    await app.dlg_info("Extracted BSPs:\n\n" + lines)


async def util_chroot(app: Any) -> None:
    target = await app.pick_bsp()
    if target is None:
        return
    soc = await app.pick_soc()
    if soc is None:
        return
    rootfs = ROOTFS(app) / "bsp" / target / "Linux_for_Tegra" / "rootfs"
    if await app.dlg_confirm("chroot", str(rootfs)):
        await app.run_cmd(
            ["sudo", str(rp(app) / "scripts" / "utils" / "chroot" / "jetson_chroot.sh"), str(rootfs), soc]
        )


async def util_view_log(app: Any) -> None:
    p = app.menu_log_path
    if not Path(p).is_file():
        await app.dlg_info("No log yet.")
        return
    text = Path(p).read_text(encoding="utf-8", errors="replace")
    if len(text) > 120_000:
        text = text[-120_000:] + "\n\n[truncated]\n"
    await app.dlg_info(text)


# --- settings ------------------------------------------------------------


async def settings_jetpack(app: Any) -> None:
    v = await app.pick_jetpack()
    if v:
        app.cfg["JETPACK"] = v
        app.persist()


async def settings_soc(app: Any) -> None:
    v = await app.pick_soc()
    if v:
        app.cfg["SOC"] = v
        app.persist()


async def settings_env(app: Any) -> None:
    v = await app.pick_env()
    if v:
        app.cfg["ENV"] = v
        app.persist()


async def settings_tag(app: Any) -> None:
    v = await app.dlg_input("Default tag", app.cfg.get("TAG", ""))
    if v is not None:
        app.cfg["TAG"] = v
        app.persist()


async def settings_token(app: Any) -> None:
    await app.ensure_access_token()
    app.persist()


async def settings_robot(app: Any) -> None:
    v = await app.dlg_input("Robot number", app.cfg.get("ROBOT_NUMBER", ""))
    if v is not None:
        app.cfg["ROBOT_NUMBER"] = v
        app.persist()


async def settings_validity(app: Any) -> None:
    v = await app.dlg_input("Validity", app.cfg.get("HOST_CERT_VALIDITY", "48h"))
    if v is not None:
        app.cfg["HOST_CERT_VALIDITY"] = v
        app.persist()


async def settings_localver(app: Any) -> None:
    v = await app.dlg_input("localversion", app.cfg.get("LOCALVERSION", ""))
    if v is not None:
        app.cfg["LOCALVERSION"] = v
        app.persist()


async def settings_kname(app: Any) -> None:
    v = await app.dlg_input("Kernel tree name", app.cfg.get("KERNEL_NAME", ""))
    if v is not None:
        app.cfg["KERNEL_NAME"] = v
        app.persist()


async def settings_arch(app: Any) -> None:
    v = await app.pick_arch()
    if v:
        app.cfg["COMPILE_ARCH"] = normalize_arch_tag(v)
        app.persist()


async def settings_toolchain(app: Any) -> None:
    await app.edit_toolchain_defaults()


async def settings_pkgcfg(app: Any) -> None:
    v = await app.dlg_input("Package defconfig", app.cfg.get("PACKAGE_CONFIG", ""))
    if v is not None:
        app.cfg["PACKAGE_CONFIG"] = v
        app.persist()


async def settings_ccfg(app: Any) -> None:
    v = await app.dlg_input("Compile --config", app.cfg.get("COMPILE_CONFIG", ""))
    if v is not None:
        app.cfg["COMPILE_CONFIG"] = v
        app.persist()


async def settings_compile_dtb(app: Any) -> None:
    v = await app.dlg_input("Compile --dtb-name", app.cfg.get("COMPILE_DTB_NAME", ""))
    if v is not None:
        app.cfg["COMPILE_DTB_NAME"] = v.strip()
        app.persist()


async def settings_package_dtb(app: Any) -> None:
    v = await app.dlg_input("Package --dtb-name", app.cfg.get("PACKAGE_DTB_NAME", ""))
    if v is not None:
        app.cfg["PACKAGE_DTB_NAME"] = v.strip()
        app.persist()


async def settings_clear(app: Any) -> None:
    if await app.dlg_confirm("Clear", "Delete .kb-menu.config and exit kb-menu?"):
        try:
            app.menu_config_path.unlink(missing_ok=True)
        except OSError:
            pass
        app.exit()
