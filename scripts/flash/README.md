# flash/

Device flashing, rootfs preparation, and live-USB helpers.

- `jetson/` — board-level Jetson flashing: bootloader, boot-order overlays,
  kernel-only flashing, rootdisk switching.
- `rootfs_prep/` — prepare an L4T rootfs (`setup_tegra_package.sh`), build
  the kernel into it (`build_kernel.sh`), apply per-robot config and flash
  (`setup_rootfs_as_robot_for_flashing.sh`,
  `flash_jetson_ALL_sdmmc_partition_qspi.sh`).
- `legacy/` — compatibility workflow for the older image-manager approach
  (`robot_image_manager.sh`) that can download/extract a prebuilt rootfs tar
  (Google Drive `--rootfs-gid` or local `--tar`) and prepare cached per-robot
  flash images.
- `live_usb/` — create bootable Ubuntu live USBs used to flash robots
  (`create_ubuntu_iso.sh`, `create_ubuntu_live_w_second_partition.sh`).

Large L4T / BSP tarballs and extracted rootfs trees live under
`scripts/rootfs/` at runtime but are gitignored.
