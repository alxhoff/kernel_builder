# flash/

Device flashing, rootfs preparation, and live-USB helpers.

- `jetson/` — board-level Jetson flashing: bootloader, boot-order overlays,
  kernel-only flashing, rootdisk switching.
- `rootfs_prep/` — prepare an L4T rootfs (`setup_rootfs.sh`,
  `setup_tegra_package.sh`), build the kernel into it (`build_kernel.sh`),
  pack / update bootloader and UEFI, and the `flash_jetson_*` full-flash
  scripts. Also includes the Docker-based flash helper
  `docker_flash_orin.sh`.
- `live_usb/` — create bootable Ubuntu live USBs used to flash robots
  (`create_ubuntu_iso.sh`, `create_ubuntu_live_w_second_partition.sh`).

Large L4T / BSP tarballs and extracted rootfs trees live under
`scripts/rootfs/` at runtime but are gitignored.
