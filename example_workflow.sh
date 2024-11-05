#!/bin/bash

# This is an example workflow that would be used for comiling and flashing a jetson with a specific kernel

python3 kernel_builder.py build
python3 kernel_builder.py clone-toolchain --toolchain-url https://github.com/alxhoff/Jetson-Linux-Toolchain --toolchain-name aarch64-buildroot-linux-gnu
python3 kernel_builder.py clone-kernel --kernel-source-url https://github.com/alxhoff/jetson-kernel --kernel-name jetson --git-tag sensing_world_v1
python3 kernel_builder.py clone-overlays --overlays-url https://github.com/alxhoff/jetson-kernel-overlays --kernel-name jetson --git-tag sensing_world_v1
python3 kernel_builder.py clone-device-tree --device-tree-url https://github.com/alxhoff/jetson-device-tree-hardware --kernel-name jetson --git-tag sensing_world_v1
python3 kernel_builder.py compile --kernel-name jetson --arch arm64 --toolchain-name aarch64-buildroot-linux-gnu --config tegra_defconfig
python3 kernel_deployer.py deploy-jetson --kernel-name jetson --ip 192.168.1.173 --user cartken

