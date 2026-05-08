# deploy/

Shell wrappers around `python/kernel_deployer.py` for shipping kernels, modules, and
Debian packages to x86, Jetson, and Raspberry Pi targets.

## Layout

- `deploy_kernel.sh` — push a compiled kernel (plus modules by default) to a
  device (wraps `kernel_deployer.py deploy-device` /
  `deploy_deployer.py deploy-jetson`).
- `deploy_debian.sh` — push a packaged `.deb` produced by `bindeb-pkg` /
  `scripts/release/compile_and_package.sh` (wraps
  `kernel_deployer.py deploy-debian`).
- `compile_and_deploy_kernel.sh` — one-shot compile + deploy flow (calls
  into `scripts/build/...` then the matching deployer).
- `update_bootloader.sh` — push a regenerated bootloader payload to a
  running Jetson over SSH and trigger a slot swap. Supports `--both-slots`
  to update A/B with a reboot in between.
- `update_uefi.sh` — push a UEFI capsule update to a running Jetson and
  set `OsIndications` so the firmware applies it on the next boot.
- `create_ekb_update.sh` — generate a BUP / UEFI capsule payload from an
  existing Linux_for_Tegra setup, ready to be pushed via the two scripts
  above.

## Conventions

- All scripts default to reading the target IP / username from
  `scripts/config/device_ip` and `scripts/config/device_username` when those
  files exist. Override with `--ip` and `--user` (or the individual script's
  equivalent flag).
- `--dry-run` is supported everywhere to preview SSH / SCP commands without
  executing them.
- `--localversion` lets you disambiguate when multiple kernel builds live in
  the same `kernels/<kernel-name>/` tree.
- For Jetson, prefer `deploy_kernel.sh` with `--dtb` to also mark the
  matching DTB as the default in `extlinux.conf`. Use `--kernel-only` to skip
  shipping modules.

For tag-based deployment (with manifest tracking, fleet parallelism, and
verification) use `scripts/release/kernel_tags.sh deploy` instead. See
[scripts/release/README.md](../release/README.md).
