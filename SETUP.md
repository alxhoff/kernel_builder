# SETUP Instructions for Kernel Builder and Deployer

This document provides setup instructions for cross-compiling and deploying Linux kernels for x86 host machines, NVIDIA Jetson boards, and Raspberry Pi.

## Dependencies

Before using the Python scripts or Dockerfile, make sure you have the following dependencies installed on your system.

### Ubuntu/Debian

To install the required dependencies on Ubuntu/Debian, run:

```bash
sudo apt update
sudo apt install python3 python3-pip docker.io openssh-client make build-essential ctags
```

Ensure that Docker is installed and running. You can enable Docker to start on boot:

```bash
sudo systemctl enable docker
sudo systemctl start docker
```

### Arch Linux

To install the required dependencies on Arch Linux, run:

```bash
sudo pacman -Syu
sudo pacman -S python openssh docker make base-devel ctags
```

Start and enable Docker:

```bash
sudo systemctl enable docker
sudo systemctl start docker
```

You may also need to add your user to the `docker` group to avoid using `sudo` for Docker commands:

```bash
sudo usermod -aG docker $USER
```

Log out and log back in for the changes to take effect.

## Setup Instructions

1. **Clone the repository**:
   
   First, clone this repository to your local machine:
   ```bash
   git clone https://github.com/your-repo/kernel-builder.git
   cd kernel-builder
   ```

2. **Install Python dependencies (optional)**:
   
   If you have any Python dependencies in the future, they can be installed with the following command:
   
   ```bash
   # pip install -r requirements.txt  # Uncomment if necessary
   ```


