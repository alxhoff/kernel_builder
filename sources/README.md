# sources/ — Tracked build inputs

Curated, version-controlled inputs that feed the build / flash workflows.
Everything in here is **tracked** in git and is fetched from the project's
GitHub repo by remote setup helpers (e.g. `setup_tegra_package.sh`,
`scripts/flash/rootfs_prep/helpers/build_kernel.sh`).

| Path | Contents |
|------|----------|
| `configs/<jetpack>/defconfig` | Curated kernel `defconfig` per JetPack version. |
| `configs/cartken.conf`, `configs/working_display.conf` | Reference snippets for camera / display patches. |
| `configs/check_config.py` | Helper to diff a built kernel `.config` against the curated `defconfig`. |
| `patches/<jetpack>/*.patch` | Per-JetPack kernel patch series (camera, GMSL, panic logger, defconfig overlays, …). |
| `patches/staging/<jetpack>/*.patch` | Staging area for in-progress / not-yet-merged patches. |
| `patches/librealsense/`, `patches/intel/`, `patches/nvidia/`, `patches/realsense/`, `patches/mengyui/` | Vendor / tooling patch buckets. |
| `pinmux/<series>/{p3737-…, p3701-…}` | NVIDIA Jetson pinmux `.conf` files (5.X for JP5, 6.X for JP6). |

## How it's consumed

- `setup_tegra_package.sh` clones `sources/patches/<jetpack>/` into the
  Linux_for_Tegra kernel tree before building.
- `scripts/release/build_and_tag.sh` syncs `sources/configs/<jetpack>/<config>`
  into the kernel source tree so kernel builds always pick up the curated
  defconfig.
- `scripts/flash/rootfs_prep/helpers/get_pinmux.sh` sparse-checks-out
  `sources/pinmux/<series>/` from the GitHub repo when the rootfs is
  being prepared on a machine that doesn't have the repo locally.
