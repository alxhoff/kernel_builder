# menu/

**menuconfig-style TUI** for kernel_builder: **Textual** (Python), with a
split option list + help panel. Same persisted config as before
(`.kb-menu.config`).

## Run

```bash
./bin/kb-menu
```

Install UI dependencies once (use a venv if your distro blocks `pip install`):

```bash
python3 -m venv .venv-kbmenu
.venv-kbmenu/bin/pip install -r python/requirements-ui.txt
```

`bin/kb-menu` prefers, in order: `$KB_MENU_PYTHON`, `.venv-kbmenu/bin/python`,
`.venv/bin/python`, then `python3`.

**Kernel tags** actions need **`jq`** (same as `scripts/release/kernel_tags.sh`).

### Legacy whiptail UI

If you need the old newt dialogs:

```bash
./scripts/menu/kb-menu-legacy.sh
```

(requires `whiptail` / libnewt)

## Layout

- **Left:** categories / actions (arrow keys, Enter to run).
- **Right:** short help for the highlighted line (menuconfig-style).
- **Esc:** back (or quit from the top menu).
- **q:** quit.
- Confirm / input / checklists open as modals; commands run in a log modal
  (output is also tee’d to `.kb-menu.last.log`).

## Main menu (categories)

| Category | Meaning |
|----------|---------|
| **Jetson BSP & rootfs** | `setup_tegra_package.sh`, robot flash rootfs, or both. Not `storage/kernels` compile. |
| **Kernel** | `kernel_builder.py` compile, `compile_and_package.sh`, Kconfig, clean/mrproper, Docker, BSP `build_kernel.sh`. |
| **Kernel tags** | `kernel_tags.sh` — manifest, deploy, verify, etc. |
| **OTA** | `create_full_ota_update.sh`, `setup_rootfs_as_robot_for_ota.sh`. |
| **Running device** | Bootloader / UEFI / EKB under `scripts/deploy/`. |
| **Workspace** | List BSPs, chroot, last log. |
| **Settings** | Edit `.kb-menu.config` defaults. |

## Persistence

`scripts/menu/.kb-menu.config` (chmod 600, gitignored) stores `KB_MENU_*`
variables — compatible with the legacy bash loader.

## Adding a workflow

1. Add an async function in `python/kb_menu/workflows.py` (or a submodule).
2. Wire it from a `MenuEntry` in `python/kb_menu/app.py` or an inner
   `MenuHubScreen` in `workflows.py`.
3. Use `app.dlg_*` helpers and `await app.run_cmd([...])` for the real command.
