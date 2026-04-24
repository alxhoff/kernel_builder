### default_flash_jetson_1_external_partition_qspi 

*DEFAULT FOR USB DEVELOPMENT*

This is the default development script that flashes the board with the bare minimum of essential partitions and the same fot the USB disk, with all kernel related stuff in the rootfs and then the minimal partitions on the USB for booting.

### default_emmc_flash_jetson_ALL_sdmmc_partition_qspi_minimal.sh

This flashes the emmc with a minimal parition scheme such that the kernel in the rootfs is booted.

### flash_jetson_ALL_sdmmc_partition_qspi

Consolidated into `scripts/rootfs/flash_jetson_ALL_sdmmc_partition_qspi.sh`. Use
its `--mode copy-kernel` flag (or legacy `--kernel`) to reproduce the staging
workflow that used to live in this directory. It still performs the "default"
NVIDIA install with the full QSPI + eMMC partition layout.

