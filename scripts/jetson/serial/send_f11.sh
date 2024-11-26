#!/bin/bash
DEVICE="/dev/serial/by-id/usb-NVIDIA_Tegra_On-Platform_Operator_TOPO0C5FB339-if03"
stty -F $DEVICE 115200
echo -e "\e[23~" > $DEVICE
