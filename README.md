# Kernel Builder, Deployer, and Debugger

Cross-compile, deploy, and debug Linux kernels for x86 host machines, NVIDIA
Jetson boards, and Raspberry Pi.

The repository is organised around three top-level Python entry points and a
hierarchy of wrapper shell scripts under `scripts/`.

- `kernel_builder.py` — build kernels, modules, and `.deb` packages (host or
  Docker).
- `kernel_deployer.py` — deploy compiled kernels, modules, and Debian packages
  to x86, Jetson, or Raspberry Pi targets.
- `kernel_debugger.py` — drive remote tracing, ftrace / trace-cmd, persistent
  logging, and module inspection on Jetson devices.

## Setup

See [.docs/SETUP.md](./.docs/SETUP.md) for installing dependencies, cloning the
repository, and preparing toolchains.

## Directory layout

```
kernel_builder.py      # build orchestrator (entry point)
kernel_deployer.py     # deploy orchestrator (entry point)
kernel_debugger.py     # debug/trace orchestrator (entry point)
bin/                   # short aliases for the most-used scripts
kernels/               # cloned kernel source trees (one per --kernel-name)
toolchains/            # cloned cross-compile toolchains
scripts/
  release/             # tagged-release workflow (build_and_tag,
                       #   kernel_tags, compile_and_package)
  build/               # kernel / module / packaging compile wrappers
  deploy/              # deploy wrappers around kernel_deployer.py
  flash/               # Jetson flashing, rootfs prep, live-USB helpers
  ota/                 # OTA payload creation and robot fleet updates
  tracing/             # ftrace / function-graph / RTCPU tracing helpers
  camera/              # v4l2, RealSense, and camera streaming tools
  can/                 # TCAN / SLCAN-FD tools + CAN log analysis
  device/              # on-target logs, serial, load, storage, system info
  cleanup/             # clean build artifacts
  ctags/               # generate/list/delete ctags source-index files
  usb_disk/            # ISO creation and USB flashing helpers
  utils/               # chroot, dtb, docker, and misc utilities
  config/              # device_ip / device_username defaults (gitignored)
```

## Short aliases (`bin/`)

The most-used entry points are exposed as short wrapper scripts in `bin/` so
you don't have to remember deep paths. For example:

```bash
./bin/tags list                         # scripts/release/kernel_tags.sh
./bin/build cartken_5_1_5_realsense     # scripts/release/build_and_tag.sh
./bin/package cartken_6_2 --localversion cartken6.2
./bin/menuconfig cartken_6_2
./bin/chroot 5.1.5
./bin/dtb extract /path/to/something.dtb
```

See [bin/README.md](./bin/README.md) for the full list. Add `bin/` to your
`$PATH` to drop the `./bin/` prefix entirely.

Every shell script reads the target device's IP and username from
`scripts/config/device_ip` and `scripts/config/device_username` when those
files are present. Templates with the `.template` suffix ship in the repo.

## 1. Build the Docker image

```bash
python3 kernel_builder.py build [--rebuild]
```

Use `--rebuild` to rebuild without the cache.

## 2. Clone sources

### Kernel source

```bash
python3 kernel_builder.py clone-kernel \
  --kernel-source-url <git-url> \
  --kernel-name <name> \
  [--git-tag <tag>]
```

### Toolchain

```bash
python3 kernel_builder.py clone-toolchain \
  --toolchain-url <git-url> \
  --toolchain-name <name> \
  [--git-tag <tag>]
```

### Overlays / device tree

```bash
python3 kernel_builder.py clone-overlays     --overlays-url <url>     --kernel-name <name> [--git-tag <tag>]
python3 kernel_builder.py clone-device-tree  --device-tree-url <url>  --kernel-name <name> [--git-tag <tag>]
```

## 3. Compile

```bash
python3 kernel_builder.py compile \
  --kernel-name <name> \
  --arch <arm64|x86_64> \
  [--toolchain-name <name>] [--toolchain-version <ver>] \
  [--rpi-model rpi3|rpi4] \
  [--config <defconfig>] \
  [--generate-ctags] \
  [--build-target kernel,dtbs,modules,bindeb-pkg] \
  [--threads N] [--clean] [--use-current-config] \
  [--localversion <str>] [--host-build] \
  [--dtb-name <name>] [--build-dtb] [--build-modules] \
  [--overlays <csv-of-dtbos>] [--dry-run]
```

Key flags:

- `--build-target` — comma-separated list (`kernel`, `dtbs`, `modules`,
  `bindeb-pkg`).
- `--host-build` — skip Docker and build directly on the host (useful on
  already-configured CI / developer machines).
- `--clean` — run `make mrproper` first.
- `--use-current-config` — seed from the running system's `/proc/config.gz`.
- `--dry-run` — print the full command without executing.

Modules are installed to `kernels/<kernel-name>/modules/` via
`INSTALL_MOD_PATH` so deployment stays predictable.

### Compile a single out-of-tree module

```bash
python3 kernel_builder.py compile-target-modules \
  --kernel-name <name> \
  --arch <arm64|x86_64> \
  --modules <path1,path2,...> \
  [--toolchain-name <name>] [--host-build] [--dry-run]
```

## 4. Deploy

### x86 host

```bash
python3 kernel_deployer.py deploy-x86 [--localversion <str>] [--dry-run]
```

### Jetson

```bash
python3 kernel_deployer.py deploy-jetson \
  --kernel-name <name> \
  --ip <device-ip> --user <user> \
  [--localversion <str>] [--dtb] [--kernel-only] [--dry-run]
```

`--dtb` marks the DTB compiled with the kernel as the default in
`extlinux.conf`. `--kernel-only` skips shipping modules.

### Generic device (Jetson or Raspberry Pi)

```bash
python3 kernel_deployer.py deploy-device \
  --ip <device-ip> --user <user> \
  [--localversion <str>] [--kernel-only] [--dry-run]
```

### Debian package

```bash
python3 kernel_deployer.py deploy-debian \
  --kernel-name <name> \
  [--localversion <str>] [--dtb-name <prefix>]
```

### Targeted out-of-tree modules only

```bash
python3 kernel_deployer.py deploy-targeted-modules \
  --kernel-name <name> --ip <device-ip> --user <user> [--dry-run]
```

## 5. Debug and trace (Jetson)

`kernel_debugger.py` wraps common on-device debugging chores over SSH:

```bash
python3 kernel_debugger.py <command> --ip <device-ip> --user <user> [...]
```

Commands include:

- `install-trace-cmd` — install `trace-cmd` on the target.
- `list-modules`, `list-tracepoints` — inventory loaded modules and available
  tracepoints.
- `start-tracing`, `stop-tracing`, `record-trace`, `retrieve-trace`,
  `report-trace` — drive ftrace and `trace-cmd record/report`.
- `start-system-tracing`, `stop-system-tracing` — broad system-wide tracing
  sessions.
- `enable-persistent-logging` — enable pstore / persistent kernel logs.
- `retrieve-logs`, `retrieve-boot-logs` — pull dmesg / boot logs back to the
  host.

Most commands accept `--dry-run` to preview the exact remote commands.

## Tag-based kernel snapshots

Tagged kernel artifacts (kernel + modules + `.deb`) can be captured, promoted,
deployed, and compared with `scripts/release/kernel_tags.sh` (short alias:
`./bin/tags`). The one-shot interactive **build → package → tag → publish**
flow is `scripts/release/build_and_tag.sh` (short alias: `./bin/build`). See
[scripts/release/README.md](./scripts/release/README.md) for the full
workflow, including fleet deployment and the manifest schema.

## Examples

Step-by-step workflows for x86, Jetson, and Raspberry Pi are in
[.docs/EXAMPLES.md](./.docs/EXAMPLES.md).
