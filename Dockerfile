# Base image
FROM ubuntu:20.04

# Set non-interactive mode for apt-get
ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-c"]

# Install dependencies
RUN apt-get update && \
    apt-get install -y \
    build-essential \
    gcc-aarch64-linux-gnu \
    gcc-arm-linux-gnueabihf \
    make \
    bc \
    bison \
    flex \
    libssl-dev \
    wget \
    git && \
    apt-get clean

# Set up work directory
WORKDIR /kernel

# Ensure make is available in PATH
ENV PATH="/bin:${PATH}"

