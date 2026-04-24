# utils/

Miscellaneous developer helpers, grouped by concern.

- `chroot/` — enter a Jetson / rootfs chroot (`jetson_chroot.sh`,
  `chroot_rootfs_tarball.sh`).
- `configs/` — `.config` diff helper (`compare_configs.sh`).
- `dtb/` — Device Tree helpers: decompile / verify / string search
  (`dtb_dts_helper.sh`, `verify_dtb.sh`, `search_for_dtb_strings.sh`).
- `kernel/` — kernel-source utilities (`list_kernels.sh`,
  `check_modules.sh`, `resolve_kernel_panic.sh`).
- `docker/` — Ubuntu container for reproducing build environments
  (`run_ubuntu_container.sh` + `Dockerfile`).
- `misc/` — everything else: `create_rootfs_tar.sh`,
  `find_realsense_devs.sh`, `gitignore_untracked.sh`.
