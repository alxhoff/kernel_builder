# Flashing a Jetson (Current + Legacy)

This document primarily covers the current `rootfs_prep` flow, and also includes
the isolated legacy `robot_image_manager.sh` compatibility path.

The flashing process now uses scripts under `scripts/flash/rootfs_prep/` and is split into:
1. Build/refresh a base JetPack rootfs.
2. Apply per-robot config (VPN + SSH CA + hostname), then flash.

## TLDR (No Repo Clone)

Assume a fresh machine with no local repo checkout.

<details>
<summary><strong>Current method (recommended)</strong></summary>

<br>

Download only `rootfs_prep` scripts:

```bash
mkdir -p jetson_rootfs_prep && \
  curl -sL https://codeload.github.com/alxhoff/kernel_builder/tar.gz/master | \
  tar -xz --strip-components=4 -C jetson_rootfs_prep \
    kernel_builder-master/scripts/flash/rootfs_prep
```

Build/refresh base rootfs:

```bash
cd jetson_rootfs_prep && \
  sudo ./setup_tegra_package.sh --jetpack 5.1.5 --soc orin --access-token glpat-... --tag v7.5.0-sshca8
```

Log in once (normal shell):

```bash
cartken account login production
```

Prepare + flash robot:

```bash
cd jetson_rootfs_prep && \
  sudo ./setup_rootfs_as_robot_for_flashing.sh --target-bsp 5.1.5 --soc orin --robot-number 915 --env production
```

Refresh stale SSH CA keys/certs only:

```bash
cd jetson_rootfs_prep && \
  sudo ./setup_rootfs_as_robot_for_flashing.sh --target-bsp 5.1.5 --soc orin --robot-number 915 --env production --refresh-ssh-ca-only
```

</details>

<details>
<summary><strong>Legacy method (only when needed)</strong></summary>

<br>

Download only `legacy` scripts:

```bash
mkdir -p jetson_legacy && \
  curl -sL https://codeload.github.com/alxhoff/kernel_builder/tar.gz/master | \
  tar -xz --strip-components=4 -C jetson_legacy \
    kernel_builder-master/scripts/flash/legacy
```

Prepare then flash:

```bash
cd jetson_legacy && \
  sudo ./robot_image_manager.sh prepare --robots 395,396 --credentials-dir ./robot_credentials && \
  sudo ./robot_image_manager.sh flash --robot 395 --password cartken
```

Legacy default credentials path:

```plain
jetson_legacy/robot_credentials/
```

`robot_credentials` is not a special provided folder name; it is just a common
local directory name. You can use any directory with `--credentials-dir`.

Required structure (robot-number folders containing cert/key pair):

```plain
<credentials-dir>/
├── 328/
│   ├── robot.crt
│   └── robot.key
├── 395/
│   ├── robot.crt
│   └── robot.key
└── 396/
    ├── robot.crt
    └── robot.key
```

</details>

## What changed vs old docs

- `robot_image_manager.sh` is no longer the flashing entry point.
- New entry points are:
  - `setup_tegra_package.sh` (base BSP/rootfs build)
  - `setup_rootfs_as_robot_for_flashing.sh` (per-robot prep + flash)
- SSH setup now targets **cartken-jetson-sshd-v2** with backend-signed host cert + user CA material baked into the rootfs before first boot.
- Package refresh is tag-driven via `--tag` and `--access-token`.
- Legacy compatibility is now available as a separate legacy script package.

## Script 1: Build the base rootfs

Use `setup_tegra_package.sh` to download/extract JetPack BSP assets, apply NVIDIA binaries, fetch Cartken packages, and run chroot setup.

```bash
sudo ./setup_tegra_package.sh \
  --jetpack 5.1.5 \
  --soc orin \
  --access-token glpat-... \
  --tag v7.5.0-sshca8
```

Useful flags:
- `--docker` run the whole setup in the standard containerized environment.
- `--rebuild` with `--docker`, force rebuild of the Docker image.
- `--inspect` with `--docker`, open shell in the container instead of running setup.
- `--skip-kernel-build`, `--skip-display-driver-build`, `--skip-pinmux`, `--skip-chroot-build` for partial/recovery workflows.
- `--no-download` reuse already downloaded tarballs.

## Script 2: Per-robot prep + flash

Use `setup_rootfs_as_robot_for_flashing.sh` after the base rootfs exists.

```bash
sudo ./setup_rootfs_as_robot_for_flashing.sh \
  --target-bsp 5.1.5 \
  --soc orin \
  --robot-number 915 \
  --env production
```

This script:
- prepares VPN material in rootfs,
- provisions `/etc/ssh/cartken_sshd/` for SSH v2,
- reruns the Cartken chroot layer,
- sets hostname + `CARTKEN_CART_NUMBER`,
- runs the flashing script.

### Credential/VPN input options

You can provide VPN credentials in one of these ways:
- Pull from reachable live robot: use `--robot-number` (and optionally `--password` for sshpass SCP).
- Local files: `--crt /path/robot.crt --key /path/robot.key`
- Zip bundle: `--zip /path/creds.zip`
- Skip VPN cert handling entirely: `--skip-vpn`

### SSH CA notes (new method)

By default the script provisions SSH CA files for `cartken-jetson-sshd-v2`.

Required for this default path:
1. `cartken-dev` installed for your user.
2. Run `cartken account login <env>` before invoking the sudo script.

If backend signing is unavailable, you can temporarily bypass this with:

```bash
--skip-ssh-ca
```

(Robot SSH service will not be fully ready until AWX writes missing material.)

## Common workflows

### Re-flash at a newer Cartken tag (without full BSP rebuild)

```bash
sudo ./setup_rootfs_as_robot_for_flashing.sh \
  --target-bsp 5.1.5 \
  --soc orin \
  --robot-number 915 \
  --env production \
  --tag v7.5.0-sshca9 \
  --access-token glpat-...
```

### Wipe stale rootfs and rebuild clean before per-robot setup

```bash
sudo ./setup_rootfs_as_robot_for_flashing.sh \
  --target-bsp 5.1.5 \
  --soc orin \
  --robot-number 915 \
  --env production \
  --tag v7.5.0-sshca9 \
  --access-token glpat-... \
  --clean-rootfs
```

### Refresh stale SSH keys/certs only (no other rootfs changes)

If robot identity/customization is already correct and only SSH material is
stale, run:

```bash
sudo ./setup_rootfs_as_robot_for_flashing.sh \
  --target-bsp 5.1.5 \
  --soc orin \
  --robot-number 915 \
  --env production \
  --refresh-ssh-ca-only
```

To override cert lifetime, add `--host-cert-validity <duration>`.  
Default host cert validity is now `7d`.

## Legacy workflow (separate path)

Use this only when you explicitly need the older process (Google Drive tarball +
cached per-robot images).

### Get legacy scripts without cloning full repo

Download the whole `legacy` folder only:

```bash
mkdir -p jetson_legacy && \
  curl -sL https://codeload.github.com/alxhoff/kernel_builder/tar.gz/master | \
  tar -xz --strip-components=4 -C jetson_legacy \
    kernel_builder-master/scripts/flash/legacy
```

Then run from that folder:

```bash
cd jetson_legacy
chmod +x ./robot_image_manager.sh
```

If you only want the single script:

```bash
mkdir -p jetson_legacy && \
  curl -fsSL https://raw.githubusercontent.com/alxhoff/kernel_builder/master/scripts/flash/legacy/robot_image_manager.sh \
    -o jetson_legacy/robot_image_manager.sh && \
  chmod +x jetson_legacy/robot_image_manager.sh
```

Note: credential files are not included in these downloads; provide them with
`--credentials-dir`, `--credentials-zip`, `--crt/--key`, or `--fetch-credentials`.

From your downloaded `jetson_legacy` folder:

```bash
cd jetson_legacy
```

### Prepare images (legacy)

Using the pre-seeded local credentials directory:

```bash
sudo ./robot_image_manager.sh prepare \
  --robots 395,396 \
  --credentials-dir ./robot_credentials
```

Single-step prepare + flash:

```bash
sudo ./robot_image_manager.sh prepare \
  --robots 395 \
  --credentials-dir ./robot_credentials \
  --flash \
  --password cartken
```

Alternative credential methods:
- `--credentials-zip /path/to/creds.zip`
- `--fetch-credentials --password cartken`
- `--crt /path/to/robot.crt --key /path/to/robot.key`

If you use `--credentials-dir`, provide a directory structured like:

```plain
<credentials-dir>/<robot-number>/robot.crt
<credentials-dir>/<robot-number>/robot.key
```

Tarball source options:
- default Google Drive id (internal default in script),
- override id with `--rootfs-gid <gid>`,
- local archive with `--tar /path/to/cartken_flash.tar.gz`.

### Flash one robot (legacy)

```bash
sudo ./robot_image_manager.sh flash \
  --robot 395 \
  --password cartken
```

Legacy outputs are cached under:

```plain
jetson_legacy/robot_images/
```

### Legacy script help (full options)

```plain
Usage: ./robot_image_manager.sh <mode> [options...]

MODES:
  prepare   Build/cache per-robot image bundles.
  flash     Flash one robot from a previously prepared bundle.

GENERAL:
  --debug                     Enable shell trace output.
  -h, --help                  Show this help message.

PREPARE:
  --robots R1,R2,...          Comma-separated robots.
  --robot-range START END     Inclusive robot range.
  --flash                     After prepare, run flash flow in same invocation.
  --flash-user USER           SSH user for watchdog step during --flash (default: cartken).
  --credentials-zip ZIP       Zip containing per-robot cert/key directories.
  --credentials-dir DIR       Directory with per-robot cert/key directories.
  --crt FILE --key FILE       Reuse one cert/key pair for all selected robots.
  --fetch-credentials         Pull certs from live robots (requires --password).
  --password PASS             SSH password for --fetch-credentials.
  --l4t-dir DIR               Linux_for_Tegra path (default: legacy cartken_flash).
  --images-dir DIR            Output image cache directory.
  --rootfs-gid GID            Google Drive file id for cartken_flash tarball.
  --ssh-key "PUBKEY"          Authorized key injected into rootfs.
  --tar PATH                  Local tarball instead of Google Drive download.

FLASH:
  --robot N                   Robot number to flash.
  --password PASS             Robot sudo password (watchdog disable step).
  --l4t-dir DIR               Linux_for_Tegra path.
  --images-dir DIR            Prepared image cache directory.
  --user USER                 SSH username for watchdog step (default: cartken).
```

## Paths/layout to expect

For the no-clone current flow (`jetson_rootfs_prep`):

```plain
jetson_rootfs_prep/bsp/<jetpack>/Linux_for_Tegra/
jetson_rootfs_prep/downloads/
```

For the no-clone legacy flow (`jetson_legacy`):

```plain
jetson_legacy/cartken_flash/Linux_for_Tegra/
jetson_legacy/robot_images/
jetson_legacy/robot_credentials/
```

## Quick reference commands

```bash
# Current method help (no-clone folder)
cd jetson_rootfs_prep
./setup_tegra_package.sh --help
./setup_rootfs_as_robot_for_flashing.sh --help

# Current method typical flow
cartken account login production
sudo ./setup_tegra_package.sh --jetpack 5.1.5 --soc orin --access-token glpat-... --tag v7.5.0-sshca8
sudo ./setup_rootfs_as_robot_for_flashing.sh --target-bsp 5.1.5 --soc orin --robot-number 915 --env production

# Legacy help (no-clone folder)
cd ../jetson_legacy
./robot_image_manager.sh --help
```