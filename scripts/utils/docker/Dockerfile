# Dockerfile for Jetson Linux_for_Tegra rootfs preparation
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

# Install essential packages
RUN apt-get update && apt-get install -y \
    build-essential \
    python3 \
    python3-pip \
    cmake \
    git \
    gdb \
    pkg-config \
    zip \
    unzip \
    tar \
    xz-utils \
    zstd \
    udev \
    usbutils \
    pciutils \
    i2c-tools \
    devmem2 \
    qemu-user-static \
    software-properties-common \
    apt-utils \
    vim \
    sudo \
    wget \
    curl \
    htop \
    iotop \
    strace \
    lsof \
    dstat \
    locate \
    rsync \
    tree \
    network-manager \
    dnsutils \
    parted \
    fdisk \
    e2fsprogs \
    btrfs-progs \
    xfsprogs \
    iperf3 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set default working directory
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]

