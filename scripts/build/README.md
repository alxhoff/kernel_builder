# build/

Shell wrappers around `kernel_builder.py` for compiling kernels, out-of-tree
modules, and Debian packages.

## Layout

- `kernel/` — full-kernel compile helpers.
  - `compile_kernel.sh` — build a kernel (wraps
    `kernel_builder.py compile`; pass-through for all flags).
  - `build_6_2.sh` — opinionated build for JetPack 6.2 kernels
    (`nvbuild.sh`-based).
  - `menuconfig_kernel.sh`, `xconfig_kernel.sh`, `nconfig_kernel.sh`,
    `savedefconfig.sh` — config targets.
  - `clean_kernel.sh`, `mrproper_kernel.sh` — cleanup targets.
  - `manage_kernels.sh` — helper to list / switch / inspect the kernels in
    `kernels/`.
  - `integrate_rtl8192eu.sh` — import the Realtek RTL8192EU vendor driver
    into a kernel tree as an in-tree staging driver.
  - `example_workflow_jetson.sh` — reference end-to-end workflow.
  - `pull_build_and_package_kernel.sh` — used by remote setup flows; fetches
    and builds a kernel over HTTPS.
- `modules/` — module-only compilation.
  - `compile_jetson_modules.sh` — compile all modules for a Jetson kernel.
  - `compile_targeted_modules.sh` — build a subset of out-of-tree modules
    (wraps `kernel_builder.py compile-target-modules`).
- `packaging/` — Debian / headers packaging.
  - `compile_kernel_headers_deb.sh` — build a headers `.deb`.

> The tagged-release workflow (`build_and_tag.sh`, `kernel_tags.sh`,
> `compile_and_package.sh`) now lives under
> [`../release/`](../release/README.md).

## Conventions

- All scripts expect kernel sources under `kernels/<kernel-name>/` at the
  repository root.
- Most accept the same flags as `kernel_builder.py compile` — see the
  top-level [README.md](../../README.md). Flags are forwarded verbatim, so
  `--dry-run`, `--clean`, `--threads`, `--build-target`, `--localversion`,
  etc. work as expected.
- `--host-build` skips Docker and builds directly on the host machine,
  useful on already-configured CI or developer machines.
- Modules are installed to `kernels/<kernel-name>/modules/` via
  `INSTALL_MOD_PATH` for predictable packaging and deployment.
