# bin/ — Short aliases for the most-used scripts

Thin wrappers around the hottest entry points in `scripts/` so you can run
them from the repo root without typing long paths. Every wrapper simply
`exec`s the real script and forwards all arguments unchanged.

| Alias | Target | What it does |
|-------|--------|--------------|
| `build` | `scripts/release/build_and_tag.sh` | Interactive one-shot **build → package → tag → publish** |
| `tags` | `scripts/release/kernel_tags.sh` | Tag management CLI (list / show / tag / promote / deploy / verify) |
| `package` | `scripts/release/compile_and_package.sh` | Low-level: compile a kernel and produce a `.deb` |
| `compile` | `scripts/build/kernel/compile_kernel.sh` | Compile a kernel (wraps `kernel_builder.py compile`) |
| `deploy` | `scripts/deploy/compile_and_deploy_kernel.sh` | Compile + deploy kernel + modules to a device |
| `menuconfig` | `scripts/build/kernel/menuconfig_kernel.sh` | `make menuconfig` on a kernel source tree |
| `mrproper` | `scripts/build/kernel/mrproper_kernel.sh` | `make mrproper` on a kernel source tree |
| `clean-builds` | `scripts/cleanup/cleanup_jetson_kernel_builds.sh` | Clean Jetson kernel build artifacts |
| `panic` | `scripts/utils/kernel/resolve_kernel_panic.sh` | Resolve kernel panic addresses against `vmlinux` |
| `chroot` | `scripts/flash/rootfs_prep/jetson_chroot.sh` | Enter a chroot into a Jetson rootfs tree |
| `dtb` | `scripts/utils/dtb/dtb_dts_helper.sh` | DTB / DTS decompile / search / verify helper |
| `logs` | `scripts/device/logs/retrieve_logs.sh` | Pull kernel / system logs from a device over SSH |
| `tegra-pkg` | `scripts/flash/rootfs_prep/setup_tegra_package.sh --docker` | Download + extract Linux_for_Tegra (Docker) |
| `ota-rootfs` | `scripts/ota/setup_rootfs_as_robot_for_ota.sh` | Setup rootfs as OTA-ready robot image |
| `kb-menu` | `python -m kb_menu` (see `python/requirements-ui.txt`) | Textual TUI: menuconfig-style hub + modals; legacy: `scripts/menu/kb-menu-legacy.sh` |
| `gen-ctags` | `scripts/ctags/generate_ctags.sh` | Generate ctags index files over kernel source |

## Usage

```bash
./bin/tags list
./bin/build cartken_5_1_5_realsense --soc orin
./bin/package cartken_6_2 --localversion cartken6.2
./bin/menuconfig cartken_6_2
./bin/deploy --ip 10.42.0.5 --user cartken
./bin/chroot 5.1.5
./bin/dtb extract /boot/dtb/tegra234-p3737-0000+p3701-0000.dtb
./bin/panic vmlinux 0xffff800010082040
```

## Installing onto your `$PATH`

The recommended way is `make install` from the repo root, which copies the
`bin/*` wrappers into `$PREFIX/bin` (default `~/.local/bin`) and the fish
completions into `$PREFIX/share/fish/vendor_completions.d/`. Each installed
copy has its `REPO_ROOT` baked in, so the wrappers keep working even when
launched from outside the repo.

```bash
make install                       # PREFIX=~/.local
make install PREFIX=/usr/local     # system-wide (sudo)
make uninstall                     # tear down
```

If you'd rather not copy the files (e.g. you want edits in `bin/` to be
picked up live), add the repo's `bin/` directly to `$PATH`:

### Fish

```fish
# ~/.config/fish/config.fish
set -gx PATH /path/to/kernel_builder/bin $PATH
source /path/to/kernel_builder/completions/kb.fish
```

### Bash / Zsh

```bash
# ~/.bashrc or ~/.zshrc
export PATH="/path/to/kernel_builder/bin:$PATH"
```

After that, `build`, `tags`, `package`, etc. work from anywhere — the
wrappers resolve the repo root relative to their own location (via
`readlink -f`), so they still call the correct scripts.

Each alias forwards its flags to the underlying script, so tab-completion
for option names is whatever the target script provides (for `tags` in
particular, see `scripts/release/kernel_tags_completion.bash`).

## Adding more aliases

Pick a short name (preferably one word, kebab-case), then drop a file like:

```bash
#!/bin/bash
set -e
REPO_ROOT="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." &> /dev/null && pwd)"
exec "$REPO_ROOT/scripts/<path>/<script>.sh" "$@"
```

`chmod +x bin/<name>` and add a row to the table above.
