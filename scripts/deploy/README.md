# deploy/

Shell wrappers around `kernel_deployer.py` for shipping kernels, modules, and
Debian packages to x86, Jetson, and Raspberry Pi targets.

## Layout

- `deploy_kernel.sh` — push a compiled kernel (plus modules by default) to a
  device (wraps `kernel_deployer.py deploy-device` /
  `deploy_deployer.py deploy-jetson`).
- `deploy_debian.sh` — push a packaged `.deb` produced by `bindeb-pkg` /
  `scripts/release/compile_and_package.sh` (wraps
  `kernel_deployer.py deploy-debian`).
- `deploy_targeted_modules.sh` — deploy a subset of out-of-tree modules
  (wraps `kernel_deployer.py deploy-targeted-modules`).
- `compile_and_deploy_kernel.sh`, `compile_and_deploy_targeted_modules.sh` —
  one-shot compile + deploy flows (call into `scripts/build/...` then the
  matching deployer).

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
