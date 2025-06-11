# Scripts and what do what

## seting_rootfs_as_robot_for_ota.sh

Pulls sources for a base and target BSP versions to compile the rootfs (including kernel and display drivers) and packages it into an OTA.

## setup_rootfs_as_robot_for_flashing.sh

This downloads a tar of our BSP sources from google drive then reconfigures them for flashing. As such it is more light weight in that it doesn't actually setup the rootfs, compile the kernel etc.

## setup_tegra_package\[_docker\].sh

The core script that pulls and build BSP sources, including kernel, display drivers etc.

## Precompile Robot System Images

### Create the images

```bash
sudo ./create_robot_images.sh --robots R1,R2,R3 --password $SSH_PASSWORD
```

### Flashing a single robot with images

```bash
sudo ./flash_single_robot_from_system_images.sh --robot $ROBOT_NUMBER
```

## The individual steps

### get_robot_rootfs.sh

```bash
./get_robot_rootfs.so
```

### get_robot_credentials.sh

Gets the credentials of all robots listed in --robots, saving them to --output.

```bash
./get_robot_credentials.sh --password cartken --robots 302,305
```

### setup_rootfs_with_robot_number.sh

Sets up hostname, VPN and SSH for the rootfs to come online as target robot

```bash
sudo ./setup_rootfs_with_robot_number.sh --robot 302
```

### create_system_images.sh

This scripts creates, in place, the system images (.img) files that are to be flashed to the robots.

```bash
sudo ./create_system_images.sh
```

### save_system_images.sh

Finds and saves all .img in the --l4t-dir and saves them in a file structure inside --output

```bash
sudo ./save_system_images.sh --output system_images/302
```

### restore_system_images.sh

Restores the .img files from the --target-images directory into the --l4t-dir ready for flashing

```bash
sudo ./restore_system_images.sh --l4t-dir 5.1.5/Linux_for_Tegra --target-images system_images/302
```

### flash_jetson_ALL_sdmmc_partition_qspi.sh

Flashes the jetson with ALL partitions on the sdmmc (on board storage) as well as the qspi bootloader memory.

```bash
sudo ./flash_jetson_ALL_sdmmc_partition_qspi.sh --l4t-dir 5.1.5/Linux_for_Tegra
```
