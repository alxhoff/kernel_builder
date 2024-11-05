# Kernel Builder and Deployer for x86 Host Machine, NVIDIA Jetson Boards, and Raspberry Pi

This document explains how to use the kernel builder and deployer scripts for cross-compiling and deploying Linux kernels for x86 host machines, NVIDIA Jetson boards, and Raspberry Pi.

## Setup Instructions

For setup instructions, including installing dependencies and cloning the repository, please refer to the [SETUP.md](SETUP.md) file.

## Usage Instructions

### Important Update: Kernel Cleaning with `mrproper`

The compile command now supports a `--clean` flag to control whether the `mrproper` command is run before building the kernel. This command removes any previous build artifacts that may interfere with the current build, providing a fresh start for the compilation process. By default, `mrproper` will be run, but it can be disabled by not using the `--clean` flag.

The project includes three main Python scripts:

- **`kernel_builder.py`**: Builds the kernel for x86, NVIDIA Jetson boards, or Raspberry Pi.
- **`kernel_deployer.py`**: Deploys the compiled kernel to x86 host machines, NVIDIA Jetson boards, or Raspberry Pi.
- **Toolchain management**: Clone and manage toolchains for building the kernel.

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
python3 kernel_builder.py clone-kernel --kernel-source-url <kernel-source-url> --kernel-name <kernel-name> [--git-tag <git-tag>]
```

**Example**:
```bash
python3 kernel_builder.py clone-kernel --kernel-source-url https://github.com/torvalds/linux.git --kernel-name jetson --git-tag v5.10
```

This command will clone the specified kernel source into the provided directory if it does not already exist. The script will also verify that the correct git tag is checked out.

### 3. Cloning a Toolchain

To cross-compile the kernel for different platforms, you may need a specific toolchain. The `clone-toolchain` command allows you to clone a toolchain and store it in a toolchains folder with a specified name.

**Command**:
```bash
python3 kernel_builder.py clone-toolchain --toolchain-url <toolchain-url> --toolchain-name <toolchain-name> [--git-tag <git-tag>]
```

**Example**:
```bash
python3 kernel_builder.py clone-toolchain --toolchain-url https://github.com/alxhoff/Jetson-Linux-Toolchain --toolchain-name jetson-toolchain --git-tag v5.10
```

This will clone the specified toolchain into the `<toolchain-directory>/<toolchain-name>` folder, which can then be used for cross-compiling.

### 4. Cloning Overlays

You may also need overlays for specific kernel configurations. The `clone-overlays` command allows you to clone overlays and add them to an existing kernel directory.

**Command**:
```bash
python3 kernel_builder.py clone-overlays --overlays-url <overlays-url> --kernel-name <kernel-name> [--git-tag <git-tag>]
```

**Example**:
```bash
python3 kernel_builder.py clone-overlays --overlays-url https://github.com/alxhoff/jetson-kernel-overlays --kernel-name jetson --git-tag main
```

This command will clone the overlays repository and add it to the specified kernel directory.

### 5. Cloning Device Tree Hardware Repository

For certain platforms, you may need device tree modifications. The `clone-device-tree` command allows you to clone a device tree hardware repository and add it to the appropriate kernel directory.

**Command**:
```bash
python3 kernel_builder.py clone-device-tree --device-tree-url <device-tree-url> --kernel-name <kernel-name> [--git-tag <git-tag>]
```

**Example**:
```bash
python3 kernel_builder.py clone-device-tree --device-tree-url https://github.com/alxhoff/jetson-device-tree --kernel-name jetson --git-tag main
```

This command will clone the device tree repository into the `<kernels>/<kernel-name>/device_tree` folder.

### 6. Compiling the Kernel (Using Docker)

Once the Docker image is built and the kernel source has been cloned, you can compile the kernel and modules for your target architecture. The host `kernels` directory will be mounted into the Docker container to ensure any changes made are reflected inside the container.

**Command**:
```bash
python3 kernel_builder.py compile --kernel-name <kernel-name> --arch <target-architecture> [--toolchain-name <toolchain-name>] [--rpi-model <rpi-model>] [--config <config-file-path>] [--generate-ctags] [--build-target <build-targets>] [--threads <number-of-threads>] [--clean] [--use-current-config]
```

**Example**:
```bash
python3 kernel_builder.py compile --kernel-name jetson --arch arm64 --toolchain-name aarch64-buildroot-linux-gnu --config tegra_defconfig --generate-ctags --build-target kernel,dtbs,modules,bindeb-pkg --threads 4 --clean --use-current-config
```

This command will run the compilation inside a Docker container, mounting the kernels, toolchain, and overlays directories as Docker volumes. Compilation now runs fully encapsulated inside Docker to ensure consistency across environments.

- The `--generate-ctags` option generates a `tags` file using `ctags` for easier code navigation.
- The `--threads` argument allows you to specify the number of threads for the kernel compilation. If not provided, all available cores will be used.
- The `--clean` argument allows you to control whether `mrproper` is run before the build process. This is useful when you need a fresh environment for building or want to avoid cleaning to save time.
- The `--build-target` argument allows you to specify one or more build targets, such as `kernel`, `dtbs`, `modules`, or `bindeb-pkg`. You can pass multiple targets as a comma-separated list.
- The `--use-current-config` argument allows you to use the current system's kernel configuration (`/proc/config.gz`) to build the new kernel with the current settings.
- **Module Installation Path**: The kernel modules are now installed into a dedicated `modules` folder inside the kernel-specific folder using `INSTALL_MOD_PATH`. This makes it easier to organize and deploy.

### 7. Deploying the Kernel

The `kernel_deployer.py` script provides commands for deploying to different devices.

#### Deploy to x86 Host Machine

This command deploys the compiled kernel and modules to an x86 host machine.

**Command**:
```bash
python3 kernel_deployer.py deploy-x86 
```

This command copies the compiled kernel image (`vmlinuz`) and modules to the appropriate locations on the x86 host machine (`/boot` and `/lib/modules/`).

#### Deploy to Jetson or Raspberry Pi

This command deploys the compiled kernel and modules to a remote device (either an NVIDIA Jetson board or a Raspberry Pi).

**Command**:
```bash
python3 kernel_deployer.py deploy-device --ip <device-ip> --user <user> [--dry-run]
```

**Example**:
```bash
python3 kernel_deployer.py deploy-device --ip 192.168.1.10 --user ubuntu --dry-run
```

This command copies the compiled kernel and modules to the specified device over SSH and SCP. The `--user` argument should be set to `ubuntu` for NVIDIA Jetson or `pi` for Raspberry Pi. The `--dry-run` option prints out the SCP commands without executing them, allowing you to verify the deployment process.

### Available Options

- **`build`**:
  - `--rebuild`: Rebuild the Docker image without using the cache.

- **`clone-kernel`**:
  - `--kernel-source-url`: The URL to the kernel source to be cloned. This can be a Git repository.
  - `--kernel-name`: Name of the kernel subfolder where the source will be cloned.
  - `--git-tag`: The Git tag to check out after cloning the kernel source. Default is `master`.

- **`clone-toolchain`**:
  - `--toolchain-url`: The URL to the toolchain to be cloned. This can be a Git repository.
  - `--toolchain-name`: Name for the toolchain subfolder to distinguish different toolchains.
  - `--git-tag`: The Git tag to check out after cloning the toolchain (e.g., `v5.10`).

- **`clone-overlays`**:
  - `--overlays-url`: The URL to the overlays repository to be cloned.
  - `--kernel-name`: Name of the kernel subfolder where overlays will be added.
  - `--git-tag`: The Git tag to check out after cloning the overlays.

- **`clone-device-tree`**:
  - `--device-tree-url`: The URL to the device tree hardware repository to be cloned.
  - `--kernel-name`: Name of the kernel subfolder where device tree will be added.
  - `--git-tag`: The Git tag to check out after cloning the device tree.

- **`compile`**:
  - `--kernel-name`: Name of the kernel subfolder to use for compilation.
  - `--arch`: Target architecture (e.g., `arm64` for Jetson). Default is `arm64`.
  - `--toolchain-name`: Name of the toolchain to use for cross-compiling.
  - `--rpi-model`: Specify the Raspberry Pi model to compile the kernel for (e.g., `rpi3` or `rpi4`).
  - `--config`: Name of the kernel configuration file to be used for compilation (e.g., `defconfig`, `tegra_defconfig`).
  - `--generate-ctags`: Generate `ctags`/`tags` file for the kernel source for easier code navigation.
  - `--build-target`: Comma-separated list of build targets (e.g., `kernel`, `dtbs`, `modules`, `bindeb-pkg`).
  - `--threads`: Number of threads to use for compilation (default: use all available cores).
  - `--clean`: Run `mrproper` to clean the kernel build directory before building.
  - `--use-current-config`: Use the current system kernel configuration for building the kernel.

- **`deploy-device`**:
  - `--ip`: IP address of the target device.
  - `--user`: Username for accessing the target device (default for Jetson: `ubuntu`, default for Raspberry Pi: `pi`).

- **`inspect`**:
  - Inspect the Docker image for debugging purposes.

- **`cleanup`**:
  - Removes the Docker image and prunes unused containers.

## Example Workflows

Please refer to the [Kernel Builder Example Workflows](EXAMPLES.md) for detailed examples of workflows for x86, NVIDIA Jetson boards, and Raspberry Pi.


