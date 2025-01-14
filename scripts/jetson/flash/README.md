### default_flash_jetson_1_external_partition_qspi 

*DEFAULT FOR USB DEVELOPMENT*

This is the default development script that flashes the board with the bare minimum of essential partitions and the same fot the USB disk, with all kernel related stuff in the rootfs and then the minimal partitions on the USB for booting.

### flash_jetson_ALL_sdmmc_partition_qspi

This script is essentially doing the "default" NVIDIA install, the same as what Cartken was originally using. There are an abundance of partitions installed all the the EMMC, with 4+ kernel locations

### flash_jetson_ALL_sdmmc_partition_qspi_minimal

*DEFAULT FOR EMMC DEVELOPMENT*

This is a slimmed down version of the default NVIDIA emmc configuration where all auxilart kernel locations have been removed such that the device boots its kernel from the rootfs.