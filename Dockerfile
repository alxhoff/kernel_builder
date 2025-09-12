FROM ubuntu:20.04

# Set environment variables to prevent interaction
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Update the base image and install dependencies
RUN echo "nameserver 8.8.8.8" > /etc/resolv.conf
RUN apt-get update && apt-get install -y \
    apt-utils \
    locales \
    build-essential \
    bc \
    ccache \
    libncurses-dev \
    bison \
    flex \
    libssl-dev \
    ctags \
    wget \
    git \
    curl \
    unzip \
    xxd \
    kmod \
    libyaml-dev \
    binutils \
    pkg-config \
    qt5-default \
    rsync \
    cpio \
	libelf-dev
RUN apt-get clean
RUN rm -rf /var/lib/apt/lists/*

# Generate and configure locale
RUN locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Create the working directory
RUN mkdir -p /builder

# Set the working directory
WORKDIR /builder

# Set up default command for the container
CMD ["/bin/bash"]

