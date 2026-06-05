# rootfs_prep/

Build, configure, and flash a Jetson rootfs.

The tooling is layered: a generic L4T rootfs is built once with
`setup_tegra_package.sh`, then per-robot configuration (SSH CA material,
hostname, env, optional VPN cert) is applied by
`setup_rootfs_as_robot_for_flashing.sh` immediately before flashing.

## Common workflows

### Flash a robot from scratch

```bash
# 1. One-time per host (or whenever you bump JetPack / kernel / drivers):
sudo ./setup_tegra_package.sh \
    --jetpack 5.1.5 --soc orin \
    --access-token glpat-... --tag v7.5.0-sshca8

# 2. Per robot, plug it in via USB-C in recovery mode and run:
cartken account login production           # one-time per shell session
sudo ./setup_rootfs_as_robot_for_flashing.sh \
    --target-bsp 5.1.5 --soc orin \
    --robot-number 915 --env production
```

`setup_rootfs_as_robot_for_flashing.sh` provisions
`/etc/ssh/cartken_sshd/` with a backend-signed host certificate and the user
CA (so cartken-sshd v2 comes up working on first boot, no AWX round-trip
required), re-runs the cartken-layer chroot, sets the hostname /
`CARTKEN_CART_NUMBER`, optionally pulls VPN certs, and then invokes the
flash script.

### Re-flash an existing rootfs at a newer cartken tag

`--tag` re-pulls the named gitlab release into the rootfs's
`/root/packages/` and re-runs the cartken-layer chroot, so you don't have
to rebuild kernel/drivers just to bump cartken-* versions:

```bash
sudo ./setup_rootfs_as_robot_for_flashing.sh \
    --target-bsp 5.1.5 --soc orin --robot-number 915 --env production \
    --tag v7.5.0-sshca9 --access-token glpat-...
```

### Refresh only stale SSH CA material in an existing rootfs

If the rootfs is already configured for the correct robot and you only need
fresh host cert / user CA material, run:

```bash
sudo ./setup_rootfs_as_robot_for_flashing.sh \
    --target-bsp 5.1.5 --soc orin --robot-number 915 --env production \
    --refresh-ssh-ca-only
```

This regenerates `/etc/ssh/cartken_sshd/` material only and exits. It skips
VPN copy, package/tag refresh, chroot, hostname updates, and flashing.

### Throw away the rootfs and start clean

When the rootfs has accumulated stale artefacts from older tooling, this
re-extracts the BSP tarball, re-applies NVIDIA binaries, and re-runs both
chroot passes (kernel/display/pinmux rebuilds skipped for speed):

```bash
sudo ./setup_rootfs_as_robot_for_flashing.sh \
    --target-bsp 5.1.5 --soc orin --robot-number 915 --env production \
    --tag v7.5.0-sshca8 --access-token glpat-... \
    --clean-rootfs
```

## Two-pass chroot architecture

Anything installed inside the rootfs goes through one of three chroot files,
each with a single responsibility:

| File | Responsibility |
|------|----------------|
| `chroot_install_os_jp5.txt` | OS layer for JetPack 5.x: apt deps, nvidia-l4t holds, stock sshd config, base cleanup. |
| `chroot_install_os_jp6.txt` | Same as above for JetPack 6.x (different NVIDIA package names, `nvidia-ctk` runtime config). |
| `chroot_install_cartken.txt` | **Cartken-layer chroot driver.** Purges every installed `cartken-*` package, installs viki, then installs debs listed in `cartken_jetson_debs.txt`. |
| `cartken_jetson_debs.txt` | **Single source of truth for which cartken-* debs to install.** One package basename per line; copied into the rootfs before chroot. |

`setup_tegra_package.sh` runs the OS layer chroot then the cartken layer
chroot back-to-back. The per-robot scripts
(`setup_rootfs_as_robot_for_flashing.sh`,
`scripts/ota/setup_rootfs_as_robot_for_ota.sh`) re-run the cartken layer so
a `--tag` swap rebuilds it without re-running the BSP setup.

`cartken_jetson_debs.txt` is intentionally self-cleaning: removing a
deb from its install list **also removes it from the rootfs** the next
time any flow runs, because the file purges every `cartken-*` before
reinstalling. There is no separate "uninstall" step to maintain.

There's also a tiny pre-`apply_binaries.sh` pass that just runs
`apt update` + `apt install -y libglib2.0-0 apt-utils` so the
freshly-extracted L4T rootfs's package manager works. It used to be a
fourth `.txt` file (`essential_chroot_setup_commands.txt`); now it's
inlined as a heredoc inside `setup_tegra_package.sh`.

## Top-level scripts

### `setup_tegra_package.sh`
Builds a generic JetPack rootfs end-to-end:
1. Downloads the L4T BSP, kernel sources, and rootfs tarball for `--jetpack`.
2. Extracts and applies NVIDIA binaries.
3. Pulls cartken `.deb` and `.whl` packages at `--tag` via `get_packages.sh`.
4. Runs the OS-layer chroot, then the cartken-layer chroot.
5. Optionally builds the kernel and (JP5) display driver against the BSP.

Pass `--docker` to re-launch the same flow inside an `ubuntu:22.04`
container so host distro / glibc versions don't matter. This is what
`scripts/ota/create_full_ota_update.sh` and `bin/tegra-pkg` use. Docker
mode also accepts `--inspect` (drop into a shell instead of running)
and `--rebuild` (force-rebuild the `jetson_builder:latest` image).

### `setup_rootfs_as_robot_for_flashing.sh`
Per-robot prep + flash. Run it after `setup_tegra_package.sh` has produced
a rootfs under `bsp/<jetpack>/Linux_for_Tegra/`. See the workflow examples
above for typical invocations; `--help` lists every flag.

Notable flags:
- `--env <production|staging|sandbox>` — backend env for SSH CA signing. Default `production`.
- `--host-cert-validity <duration>` — host cert lifetime baked into the rootfs. Default `7d`. AWX renews it on first connect.
- `--skip-ssh-ca` — skip provisioning `/etc/ssh/cartken_sshd/`. cartken-sshd will fail to start until AWX writes the missing files.
- `--refresh-ssh-ca-only` — refresh only `/etc/ssh/cartken_sshd/` material and exit (no VPN/tag/chroot/hostname/flash changes).
- `--tag <gitlab tag>` + `--access-token <tok>` — re-pull cartken packages from a gitlab release and re-run the cartken-layer chroot.
- `--clean-rootfs` — wipe and rebuild the rootfs (kernel/drivers/pinmux rebuilds skipped). Requires `--tag` and `--access-token`.
- `--skip-vpn` — skip the OpenVPN cert pull. Useful when flashing without network access to the old robot.

The script reads the SSH CA / cartken-dev session from `$SUDO_USER`'s
home; run `cartken account login <env>` in your normal shell first.

### `jetson_chroot.sh`
Chroot driver for the L4T rootfs: mounts `/proc`, `/sys`, `/dev`, sets up
Orin fakeroot shims, and optionally runs a command file line-by-line.
Copied into `Linux_for_Tegra/` by `setup_tegra_package.sh` alongside the
other rootfs_prep scripts. Also reachable via `bin/chroot`.

### `flash_jetson_ALL_sdmmc_partition_qspi.sh`
Full-flash of every sdmmc partition + QSPI bootloader. Invoked by
`setup_rootfs_as_robot_for_flashing.sh` at the end; can also be run
standalone if you've already prepared a rootfs.

## Helpers (`helpers/`)

Internal scripts that the top-level entry points call but you should not
need to invoke directly. Kept in a subdirectory so `ls` at the rootfs_prep
root only shows the things a user actually runs.

`setup_tegra_package.sh` flat-copies everything in `helpers/` into the
generated `Linux_for_Tegra/` so the chroot driver and the in-rootfs scripts
can reference each other by basename.

### Provisioning helpers (used by the top-level entry points)
- `helpers/fetch_user_ca_pubkey.py` — fetches Cartken user-CA public keys
  via `cartken-dev`'s `AuthTokenManager`. Called by
  `setup_rootfs_as_robot_for_flashing.sh` while provisioning
  `/etc/ssh/cartken_sshd/`.
- `helpers/get_packages.sh` — pulls `cartken-jetson-debians` and
  `cartken-wheels` generic packages from GitLab Packages at a given tag.
  Wipes the local `packages/` dir first so dropped debs don't linger.
- `helpers/get_pinmux.sh` — fetches pinmux files for the target SoC.

### Kernel / driver builds (chained from `helpers/build_kernel.sh`)
- `helpers/build_kernel.sh` — builds the kernel against the BSP toolchain.
- `helpers/build_display_driver.sh` — JP5-only out-of-tree NVIDIA display
  driver.
- `helpers/build_third_party_drivers.sh` /
  `helpers/build_third_party_drivers_jp6.sh` — out-of-tree driver
  framework. JP5 path is currently a no-op (drivers in-tree, see
  `scripts/build/kernel/integrate_rtl*.sh`); JP6 still builds rtl8192eu /
  rtl88x2bu.

## Related tooling outside this directory

Operational scripts that used to live here have been moved to better-fit
homes:

| Was here | Now lives at |
|----------|--------------|
| `update_bootloader.sh`, `update_uefi.sh`, `create_ekb_update.sh` | `scripts/deploy/` |
| `move_cartken_flash.sh`, `disc_backup.sh` | `scripts/device/storage/` |
| `get_system_information.sh`, `compare_registers.sh` | `scripts/device/system_info/` |
| `install_kernel_deps.sh` | `scripts/build/` |
| `get_docker.sh` | `scripts/utils/docker/` |
| `jetson_chroot.sh` | lives here in `rootfs_prep/` (was `scripts/utils/chroot/`) |
| `stability_test/setup_stability_test.sh` | `scripts/device/load/` (alongside `docker_stability_test.sh`) |

Removed entirely (deprecated): `docker_flash_orin.sh` (referenced a
non-existent `cartken-flash` binary), `build_and_flash_jp62.sh`
(superseded by `setup_tegra_package.sh --jetpack 6.2`), `rtl8192eu.sh` /
`rtl88x2bu.sh` (replaced by in-tree integration in
`scripts/build/kernel/integrate_rtl*.sh`).

## Layout at runtime

Source layout (what's tracked in git):

```
rootfs_prep/
├── setup_tegra_package.sh                  # entry point: build the BSP rootfs
├── setup_rootfs_as_robot_for_flashing.sh   # entry point: per-robot config + flash
├── jetson_chroot.sh                        # chroot driver (also copied into Linux_for_Tegra/)
├── flash_jetson_ALL_sdmmc_partition_qspi.sh # standalone-runnable flash driver
├── chroot_install_os_jp{5,6}.txt           # OS-layer chroot (Pass 1/2)
├── chroot_install_cartken.txt              # cartken-layer chroot (Pass 2/2)
├── cartken_jetson_debs.txt                 # deb manifest (one basename per line)
├── helpers/                                # internal helpers, not user-callable
│   ├── get_packages.sh
│   ├── get_pinmux.sh
│   ├── fetch_user_ca_pubkey.py
│   ├── build_kernel.sh
│   ├── build_display_driver.sh
│   └── build_third_party_drivers{,_jp6}.sh
├── certs/
└── README.md
```

Runtime layout (what `setup_tegra_package.sh` produces, all gitignored):

```
rootfs_prep/
├── downloads/                              # multi-GB BSP / kernel-source / rootfs tarballs
│   ├── jetson_linux_*.tbz2
│   ├── public_sources.tbz2
│   └── tegra_linux_sample-root-filesystem_*.tbz2
└── bsp/
    └── <jetpack-version>/                  # e.g. bsp/5.1.5/
        └── Linux_for_Tegra/
            ├── rootfs/                     # extracted L4T rootfs, modified in-place
            │   ├── etc/ssh/cartken_sshd/   # written by setup_rootfs_as_robot_for_flashing.sh
            │   └── root/packages/          # cartken debs + wheels at the current --tag
            ├── kernel/                     # built kernel artefacts
            ├── packages/                   # raw download of cartken packages
            ├── jetson_chroot.sh            # copied from rootfs_prep/
            ├── chroot_install_os_jp{5,6}.txt
            ├── chroot_install_cartken.txt
            ├── flash_jetson_ALL_sdmmc_partition_qspi.sh
            └── <flat copy of every helpers/ script>
```

`downloads/`, `bsp/`, and the various build artefacts (`*.tbz2`, `*.deb`,
`*.ko`, etc.) are gitignored. Helpers in `helpers/` are flat-copied into
`Linux_for_Tegra/` so the chroot driver and the in-rootfs scripts can
reference each other by basename without caring about the source layout.

Legacy BSP dirs sitting at `rootfs_prep/<version>/` (from before the
`bsp/` relocation) are auto-migrated into `bsp/<version>/` on the next
`setup_tegra_package.sh` run.
