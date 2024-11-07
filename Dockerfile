FROM ubuntu:20.04

# Set environment variables to prevent interaction
ENV DEBIAN_FRONTEND=noninteractive

# Update the base image and install dependencies
RUN apt-get update && apt-get install -y \
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
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create the working directory
RUN mkdir -p /builder

# Set the working directory
WORKDIR /builder

# Set up default command for the container
CMD ["/bin/bash"]

