# Kernel Builder and Deployer for x86 Host Machine, NVIDIA Jetson Boards, and Raspberry Pi

This project provides a streamlined way to cross-compile and deploy Linux kernels for x86 host machines, NVIDIA Jetson boards, and Raspberry Pi using Docker. It consists of two main Python scripts: `kernel_builder.py` for building the kernel and `kernel_deployer.py` for deploying the compiled kernel.

## Features

- **Docker-based environment**: Isolates the build environment for cross-compiling kernels, avoiding issues with system-specific dependencies.
- **Flexible kernel compilation**: Allows you to specify the kernel source URL, target architecture, cross-compiler, and device tree for different platforms (e.g., ARM64 for Jetson devices and Raspberry Pi).
- **Supports Ubuntu/Debian and Arch Linux**: Provides installation instructions for both distributions.
- **Logging for Troubleshooting**: Provides detailed logs for each step of the process to assist with troubleshooting.
- **Automated Cross-Compiler Selection**: Automatically selects the correct cross-compiler based on the target architecture.
- **Deploy to x86, Jetson, and Raspberry Pi**: Easily deploy compiled kernels to x86 hosts, NVIDIA Jetson boards, and Raspberry Pi.
- **Host Directory Mounting**: The Docker container is configured to mount both the output directory and the kernel source directory from the host, making the compiled kernel and kernel source changes directly available on the host machine.
- **Kernel Cloning Check**: Checks if the kernel source directory already exists before cloning, preventing redundant cloning operations.
- **Cross-Compiler Check**: Ensures that the required cross-compiler is installed before attempting to build the kernel.
- **Architecture-Specific Output Directories**: Organizes the output by creating architecture-specific subdirectories for each compiled kernel.

## Dependencies

Before using the Python scripts or Dockerfile, make sure you have the following dependencies installed on your system.

### Ubuntu/Debian

To install the required dependencies on Ubuntu/Debian, run:

```bash
sudo apt update
sudo apt install python3 python3-pip docker.io openssh-client make build-essential
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
sudo pacman -S python openssh docker make base-devel
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

## Usage Instructions

The project includes two main Python scripts:

- **`kernel_builder.py`**: Builds the kernel for x86, NVIDIA Jetson boards, or Raspberry Pi.
- **`kernel_deployer.py`**: Deploys the compiled kernel to x86 host machines, NVIDIA Jetson boards, or Raspberry Pi.

### 1. Building the Docker Image

The `kernel_builder.py` script provides several commands, starting with the `build` command to create the Docker image with the necessary cross-compilation environment.

**Command**:
```bash
python3 kernel_builder.py build [--rebuild]
```

If the `--rebuild` argument is provided, the Docker image will be rebuilt without using the cache.

### 2. Cloning the Kernel Source

Instead of cloning the kernel source inside the Dockerfile, it can now be done via the script to allow multiple kernel sources to be handled easily. The script will also check if the kernel source directory already exists to prevent redundant cloning.

**Command**:
```bash
python3 kernel_builder.py clone-kernel --kernel-source-url <kernel-source-url> --kernel-dir <kernel-directory> [--git-tag <git-tag>]
```

**Example**:
```bash
python3 kernel_builder.py clone-kernel --kernel-source-url https://github.com/torvalds/linux.git --kernel-dir $(pwd)/kernel/jetson --git-tag v5.10
```

This command will clone the specified kernel source into the provided directory if it does not already exist. The script will also verify that the correct git tag is checked out.

### 3. Compiling the Kernel

Once the Docker image is built and the kernel source has been cloned, you can compile the kernel and modules for your target architecture. The host `kernel` directory will be mounted into the Docker container to ensure any changes made are reflected inside the container.

**Command**:
```bash
python3 kernel_builder.py compile --output-dir <output-directory> --kernel-dir <kernel-directory> --arch <target-architecture> [--cross-compile <cross-compiler-prefix>] [--device-tree <device-tree-directory>] [--rpi-model <rpi-model>]
```

**Example**:
```bash
python3 kernel_builder.py compile --output-dir $(pwd)/output --kernel-dir $(pwd)/kernel/jetson --arch arm64 --device-tree $(pwd)/dtb
```

This will compile the kernel and modules for the specified architecture (e.g., `arm64` for Jetson) and store the output in an architecture-specific subdirectory under the specified output directory. The script also checks that the required cross-compiler is installed before attempting to compile the kernel. If compiling for a Raspberry Pi, use the `--rpi-model` option (e.g., `rpi3` or `rpi4`).

### 4. Deploying the Kernel

The `kernel_deployer.py` script provides commands for deploying to different devices.

#### Deploy to x86 Host Machine

This command deploys the compiled kernel and modules to an x86 host machine.

**Command**:
```bash
python3 kernel_deployer.py deploy-x86 --output-dir <output-directory>
```

**Example**:
```bash
python3 kernel_deployer.py deploy-x86 --output-dir $(pwd)/output
```

This command copies the compiled kernel image (`vmlinuz`) and modules to the appropriate locations on the x86 host machine (`/boot` and `/lib/modules/`).

#### Deploy to NVIDIA Jetson Board

This command deploys the compiled kernel, modules, and device tree files to an NVIDIA Jetson board.

**Command**:
```bash
python3 kernel_deployer.py deploy-jetson --output-dir <output-directory> --jetson-ip <jetson-ip-address> [--jetson-user <username>]
```

**Example**:
```bash
python3 kernel_deployer.py deploy-jetson --output-dir $(pwd)/output --jetson-ip 192.168.1.10 --jetson-user ubuntu
```

#### Deploy to Raspberry Pi

This command deploys the compiled kernel, modules, and device tree files to a Raspberry Pi.

**Command**:
```bash
python3 kernel_deployer.py deploy-rpi --output-dir <output-directory> --rpi-ip <rpi-ip-address> [--rpi-user <username>]
```

**Example**:
```bash
python3 kernel_deployer.py deploy-rpi --output-dir $(pwd)/output --rpi-ip 192.168.1.15 --rpi-user pi
```

### 5. Inspecting the Docker Image

If you need to inspect the Docker image for troubleshooting or to verify the build environment, you can open a bash shell inside the Docker container using the following command:

**Command**:
```bash
python3 kernel_builder.py inspect --output-dir <output-directory>
```

**Example**:
```bash
python3 kernel_builder.py inspect --output-dir $(pwd)/output
```

This command will open an interactive bash shell within the Docker container, allowing you to inspect the contents and verify the build environment.

### Available Options

- **`build`**:
  - `--rebuild`: Rebuild the Docker image without using the cache.

- **`clone-kernel`**:
  - `--kernel-source-url`: The URL to the kernel source to be cloned. This can be a Git repository.
  - `--kernel-dir`: Directory where the kernel source will be cloned.
  - `--git-tag`: The Git tag to check out after cloning the kernel source. Default is `master`.

- **`compile`**:
  - `--output-dir`: Directory where the compiled kernel and modules will be stored.
  - `--kernel-dir`: Directory on the host where the kernel source is located.
  - `--arch`: Target architecture (e.g., `arm64` for Jetson). Default is `arm64`.
  - `--cross-compile`: Cross-compiler prefix (e.g., `aarch64-linux-gnu-` for ARM64). If not provided, it will be determined automatically based on the architecture or Raspberry Pi model.
  - `--device-tree`: Directory to store the compiled device tree files.
  - `--rpi-model`: Specify the Raspberry Pi model to compile the kernel for (e.g., `rpi3` or `rpi4`).

- **`deploy-x86`**:
  - `--output-dir`: Directory on the host where the compiled kernel and modules are stored.

- **`deploy-jetson`**:
  - `--output-dir`: Directory on the host where the compiled kernel and modules are stored.
  - `--jetson-ip`: IP address of the NVIDIA Jetson board.
  - `--jetson-user`: Username for accessing the NVIDIA Jetson board (default: `ubuntu`).

- **`deploy-rpi`**:
  - `--output-dir`: Directory on the host where the compiled kernel and modules are stored.
  - `--rpi-ip`: IP address of the Raspberry Pi.
  - `--rpi-user`: Username for accessing the Raspberry Pi (default: `pi`).

- **`inspect`**:
  - `--output-dir`: Directory to mount inside the Docker container during inspection.

- **`cleanup`**:
  - Removes the Docker image and prunes unused containers.

## Example Workflows

### x86 Host Machine Workflow

1. **Build the Docker Image**:
   ```bash
   python3 kernel_builder.py build
   ```

2. **Clone the Kernel Source**:
   ```bash
   python3 kernel_builder.py clone-kernel --kernel-source-url https://github.com/torvalds/linux.git --kernel-dir $(pwd)/kernel/x86
   ```

3. **Compile the Kernel for x86**:
   ```bash
   python3 kernel_builder.py compile --output-dir $(pwd)/output --kernel-dir $(pwd)/kernel/x86 --arch x86_64
   ```

4. **Deploy to x86 Host Machine**:
   ```bash
   python3 kernel_deployer.py deploy-x86 --output-dir $(pwd)/output
   ```

### NVIDIA Jetson (ARM64) Workflow

1. **Build the Docker Image**:
   ```bash
   python3 kernel_builder.py build
   ```

2. **Clone the Kernel Source**:
   ```bash
   python3 kernel_builder.py clone-kernel --kernel-source-url git://nv-tegra.nvidia.com/3rdparty/canonical/linux-jammy.git --kernel-dir $(pwd)/kernel/jetson --git-tag jetson_36.4
   ```

3. **Compile the Kernel for Jetson (ARM64)**:
   ```bash
   python3 kernel_builder.py compile --output-dir $(pwd)/output --kernel-dir $(pwd)/kernel/jetson --arch arm64 --device-tree $(pwd)/dtb
   ```

4. **Deploy to NVIDIA Jetson Board**:
   ```bash
   python3 kernel_deployer.py deploy-jetson --output-dir $(pwd)/output --jetson-ip 192.168.1.10 --jetson-user ubuntu
   ```

### Raspberry Pi Workflow

1. **Build the Docker Image**:
   ```bash
   python3 kernel_builder.py build
   ```

2. **Clone the Kernel Source**:
   ```bash
   python3 kernel_builder.py clone-kernel --kernel-source-url https://github.com/raspberrypi/linux.git --kernel-dir $(pwd)/kernel/rpi --git-tag rpi-5.10.y
   ```

3. **Compile the Kernel for Raspberry Pi**:
   ```bash
   python3 kernel_builder.py compile --output-dir $(pwd)/output --kernel-dir $(pwd)/kernel/rpi --arch arm --rpi-model rpi4
   ```

4. **Deploy to Raspberry Pi**:
   ```bash
   python3 kernel_deployer.py deploy-rpi --output-dir $(pwd)/output --rpi-ip 192.168.1.15 --rpi-user pi
   ```

## Troubleshooting

- **Docker Issues**: Ensure Docker is running and that your user is in the `docker` group (to avoid using `sudo`).
- **Kernel Source URL**: Verify that the kernel source URL is correct and accessible (it must be a public repository or a downloadable tarball).
- **Cross-Compiler Issues**: If the cross-compiler is not detected correctly, try specifying it explicitly using the `--cross-compile` option. The script also checks for cross-compiler availability before starting the build.
- **Permission Denied**: Ensure you have the necessary permissions to copy files to `/boot` and `/lib/modules/` on the target machine. You may need to run the command with `sudo`.
- **SSH Connection Issues**: Verify that the IP address of the Jetson board or Raspberry Pi is correct and that SSH access is enabled.
- **Missing Files**: Ensure that the `output-dir` contains the compiled kernel image (`vmlinuz` or `Image`), modules, and DTBs.
- **Missing Dependencies**: If you encounter missing dependency errors during the Docker build, make sure that all required tools are listed in the `RUN apt-get install` command in the Dockerfile and try rebuilding the image.

