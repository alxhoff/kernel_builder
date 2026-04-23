# Kernel Builder Example Workflows

Workflows for using `kernel_builder.py`, `kernel_deployer.py`, and
`kernel_debugger.py` on x86 host machines, NVIDIA Jetson boards, and
Raspberry Pi.

Most of the shell helpers live under `scripts/` — see the top-level
[README.md](../README.md) for the current folder layout.

## x86 Host Machine

1. **Build the Docker image**:
   ```bash
   python3 kernel_builder.py build
   ```

2. **Clone the kernel source**:
   ```bash
   python3 kernel_builder.py clone-kernel \
     --kernel-source-url https://github.com/torvalds/linux.git \
     --kernel-name x86
   ```

3. **Compile for x86**:
   ```bash
   python3 kernel_builder.py compile \
     --kernel-name x86 --arch x86_64 \
     --config defconfig \
     --build-target kernel,modules \
     --threads 4
   ```

4. **Deploy to the x86 host**:
   ```bash
   python3 kernel_deployer.py deploy-x86
   ```
   `deploy-x86` accepts `--dry-run` and `--localversion`. It copies
   `vmlinuz` + modules into `/boot` and `/lib/modules/`.

## NVIDIA Jetson (ARM64)

1. **Build the Docker image**:
   ```bash
   python3 kernel_builder.py build
   ```

2. **Clone the kernel source**:
   ```bash
   python3 kernel_builder.py clone-kernel \
     --kernel-source-url https://github.com/alxhoff/jetson-kernel \
     --kernel-name jetson --git-tag sensing_world_v1
   ```

3. **Clone the toolchain**:
   ```bash
   python3 kernel_builder.py clone-toolchain \
     --toolchain-url https://github.com/alxhoff/Jetson-Linux-Toolchain \
     --toolchain-name aarch64-buildroot-linux-gnu \
     --git-tag sensing_world_v1
   ```

4. **Clone overlays / device tree (optional)**:
   ```bash
   python3 kernel_builder.py clone-overlays \
     --overlays-url https://github.com/alxhoff/jetson-kernel-overlays \
     --kernel-name jetson

   python3 kernel_builder.py clone-device-tree \
     --device-tree-url https://github.com/alxhoff/jetson-device-tree-hardware \
     --kernel-name jetson --git-tag sensing_world_v1
   ```

5. **Compile for Jetson (ARM64)**:
   ```bash
   python3 kernel_builder.py compile \
     --kernel-name jetson --arch arm64 \
     --toolchain-name aarch64-buildroot-linux-gnu \
     --config tegra_defconfig \
     --generate-ctags \
     --build-target kernel,dtbs,modules \
     --threads 4
   ```
   The compilation runs inside Docker by default. Pass `--host-build` to
   skip Docker and use the host toolchain directly.

6. **Deploy to a Jetson board**:
   ```bash
   python3 kernel_deployer.py deploy-jetson \
     --kernel-name jetson \
     --ip 192.168.1.10 --user ubuntu \
     [--localversion <str>] [--dtb] [--kernel-only] [--dry-run]
   ```
   `--dtb` promotes the compiled DTB to the device default in
   `extlinux.conf`. `--kernel-only` skips module deployment.

7. **Deploy a `.deb` package** (built via `--build-target bindeb-pkg` or
   `scripts/build/packaging/compile_and_package.sh`):
   ```bash
   python3 kernel_deployer.py deploy-debian \
     --kernel-name jetson \
     [--localversion <str>] [--dtb-name <prefix>]
   ```

## Raspberry Pi

1. **Build the Docker image**:
   ```bash
   python3 kernel_builder.py build
   ```

2. **Clone the kernel source**:
   ```bash
   python3 kernel_builder.py clone-kernel \
     --kernel-source-url https://github.com/raspberrypi/linux.git \
     --kernel-name rpi --git-tag rpi-5.10.y
   ```

3. **Compile for Raspberry Pi**:
   ```bash
   python3 kernel_builder.py compile \
     --kernel-name rpi --arch arm \
     --toolchain-name arm-buildroot-linux-gnueabihf \
     --rpi-model rpi4 \
     --config bcm2711_defconfig \
     --generate-ctags \
     --build-target kernel,dtbs,modules \
     --threads 4
   ```

4. **Deploy**:
   ```bash
   python3 kernel_deployer.py deploy-device \
     --ip 192.168.1.15 --user pi \
     [--localversion <str>] [--kernel-only] [--dry-run]
   ```

## Targeted out-of-tree modules

Build a subset of modules without rebuilding the full kernel:

```bash
python3 kernel_builder.py compile-target-modules \
  --kernel-name jetson --arch arm64 \
  --toolchain-name aarch64-buildroot-linux-gnu \
  --modules drivers/my_module,drivers/another
```

Deploy only those modules:

```bash
python3 kernel_deployer.py deploy-targeted-modules \
  --kernel-name jetson --ip 192.168.1.10 --user ubuntu
```

Or use the convenience shell wrappers:

```bash
./scripts/build/modules/compile_targeted_modules.sh   # compile
./scripts/deploy/deploy_targeted_modules.sh           # deploy
./scripts/deploy/compile_and_deploy_targeted_modules.sh  # both
```

## Tag-based builds (recommended for production)

For reproducible builds that record the kernel, `.deb`, `.config`, and git
state:

```bash
./scripts/build/kernel/build_and_tag.sh cartken_5_1_5_realsense --soc orin
./scripts/tags/kernel_tags.sh deploy 170426 --ip 10.42.0.5 --install
./scripts/tags/kernel_tags.sh verify 170426 --ip 10.42.0.5
```

Full workflow, including fleet deployment and the manifest schema, is in
[../scripts/tags/README.md](../scripts/tags/README.md).

## Debugging and tracing (Jetson)

`kernel_debugger.py` wraps common on-device debug chores over SSH:

```bash
python3 kernel_debugger.py enable-persistent-logging \
  --ip 192.168.1.10 --user root

python3 kernel_debugger.py retrieve-boot-logs \
  --ip 192.168.1.10 --user root \
  --destination-path /tmp/boot_logs

python3 kernel_debugger.py record-trace \
  --ip 192.168.1.10 --user root \
  --tracepoints irq:irq_handler_entry,sched:sched_switch
```

All subcommands support `--dry-run` to print the remote commands without
executing them.

## Inspecting the Docker image

Open a shell inside the build Docker container:

```bash
python3 kernel_builder.py inspect
```

The `kernels/` and `toolchains/` directories are mounted under `/builder`
inside the container.

## Cleaning up Docker resources

```bash
python3 kernel_builder.py cleanup
```

Removes the `kernel_builder` Docker image and prunes unused containers.

## Notes

- The Docker-based build is the default; pass `--host-build` to any
  `compile` invocation (or matching shell wrapper) to build on the host
  instead.
- All necessary directories (kernel source, toolchain) are mounted into
  Docker as volumes under `/builder`.
- Most shell helpers default to reading the target device's IP and username
  from `scripts/config/device_ip` and `scripts/config/device_username`.
