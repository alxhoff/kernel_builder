# menu/

`menuconfig`-style TUI for the kernel_builder workflows. Single-file
whiptail front end that exposes the rootfs_prep / OTA / kernel-rebuild /
deploy entry points as guided forms instead of long flag-laden invocations.

## Run

```bash
./bin/kb-menu
```

(or `./scripts/menu/kb-menu.sh` directly)

Requires `whiptail` (Ubuntu/Debian: `sudo apt install whiptail`; Arch /
Manjaro: `sudo pacman -S libnewt`). No other deps.

## Top-level menu

| Item | Wraps |
|------|-------|
| Build BSP rootfs | `scripts/flash/rootfs_prep/setup_tegra_package.sh` (with optional `--docker`) |
| Configure & flash robot | `scripts/flash/rootfs_prep/setup_rootfs_as_robot_for_flashing.sh` |
| Build + flash | Chains the two above with shared values |
| OTA workflows | `scripts/ota/create_full_ota_update.sh`, `scripts/ota/setup_rootfs_as_robot_for_ota.sh` |
| Kernel rebuild | `helpers/build_kernel.sh` inside an extracted BSP |
| Deploy | `scripts/deploy/update_bootloader.sh`, `update_uefi.sh`, `create_ekb_update.sh` |
| Utilities | List extracted BSPs, drop into `jetson_chroot.sh`, view last-run log |
| Settings | Edit persisted defaults |

Each leaf collects its inputs through a series of whiptail forms (radio
list / inputbox / passwordbox / checklist), shows you a confirmation
dialog with the assembled values, and then exits whiptail and runs the
real script with normal terminal output. After the script exits the
menu reappears.

## Persistence

All form values land in `scripts/menu/.kb-menu.config` (chmod 600,
gitignored) so re-running pre-fills your previous choices — the same
ergonomics as kernel `make menuconfig`'s `.config`.

This file may contain a GitLab access token. It's never committed
(`.gitignore`'d) but it does live on disk in plain text, just like a
`~/.netrc`. If you'd rather not persist it, clear it from
**Settings → Access token → clear** and the TUI will prompt for it on
each run that needs it.

## Logs

The most recent command's full output is tee'd to
`scripts/menu/.kb-menu.last.log` (also gitignored) and viewable from
**Utilities → View last command log**.

## Adding a new workflow

`kb-menu.sh` is one file with one menu function per workflow. To add a
new one:

1. Define `menu_<thing>()` that collects inputs via the existing
   `prompt_*` / `form_advanced_options` / `wt --menu` helpers, then
   builds an `cmd=( ... )` array and finishes with
   `confirm_run` + `run_cmd "${cmd[@]}"`.
2. Add an entry to the relevant `wt --menu` (top-level or a submenu).

Re-use the existing helpers — `prompt_jetpack`, `prompt_soc`,
`prompt_env`, `discover_bsps`, `ensure_access_token`,
`form_advanced_options` — rather than re-rolling the same prompts.
