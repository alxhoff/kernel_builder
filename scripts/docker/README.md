# Jetson Kernel Management Scripts

This README provides an overview of the scripts designed to manage kernel building, deployment, and configuration for Jetson devices. Each script automates a specific workflow, which can save considerable time and reduce errors in kernel management.

## Script Overview

### 1. `clean_jetson_kernel.sh`
- **Purpose**: This script is used to clean the kernel build directory for a Jetson kernel. It runs `make clean` or similar targets to ensure a clean state before starting a new build.
- **Usage**: The script navigates to the appropriate kernel directory and executes the `make clean` command. This ensures that any old artifacts from previous builds are removed before starting a fresh compilation.

### 2. `compile_and_deploy_jetson.sh`
- **Purpose**: This script compiles the kernel for a Jetson device and subsequently deploys the compiled kernel image and modules to the device.
- **Usage**: The script first builds the kernel, generating all necessary binaries and modules. It then uses SCP to transfer the compiled kernel and modules to the Jetson device. The script handles both building and deployment, making it ideal for those who need an end-to-end process.

### 3. `compile_jetson_kernel.sh`
- **Purpose**: This script compiles the kernel for a Jetson device.
- **Usage**: Similar to `compile_and_deploy_jetson.sh`, but without the deployment step. This script is useful when you want to perform testing on your local machine before deploying to the target device.

### 4. `compile_jetson_modules.sh`
- **Purpose**: This script specifically compiles the kernel modules for a Jetson kernel.
- **Usage**: The script targets the compilation of kernel modules only, which is useful for those who want to make changes to drivers or other modular components of the kernel without having to recompile the entire kernel.

### 5. `deploy_only_jetson.sh`
- **Purpose**: Deploys a precompiled kernel image and modules to the Jetson device.
- **Usage**: This script is useful when the kernel has already been compiled and you simply need to transfer the files to the target Jetson device. The script handles copying the kernel image, device tree blobs, and modules to their appropriate locations.

### 6. `example_workflow_jetson.sh`
- **Purpose**: An example script that demonstrates a full workflow, including building, deploying, and configuring a kernel for a Jetson device.
- **Usage**: Use this script as a reference or a basis for creating custom workflows. It encompasses all the major steps involved in kernel building and deployment.

### 7. `menuconfig_jetson_kernel.sh`
- **Purpose**: Opens the `menuconfig` configuration utility for the Jetson kernel.
- **Usage**: The `menuconfig` utility provides an interactive interface for configuring kernel options. This script launches `make menuconfig` within the kernel source tree, allowing users to customize their kernel settings.

### 8. `mrproper_jetson_kernel.sh`
- **Purpose**: Cleans the kernel source tree thoroughly.
- **Usage**: Similar to `clean_jetson_kernel.sh`, but more thorough. This script runs `make mrproper` to remove all generated files, restoring the source tree to its original state. It is especially useful when you encounter persistent build issues and need a truly fresh start.

## Script Usage
- All scripts are intended to be run from the root directory of the repository.
- The scripts will automatically determine their paths and use the appropriate kernel source, toolchain, and Jetson device configurations.
- Some scripts, such as `compile_and_deploy_jetson.sh` and `deploy_only_jetson.sh`, will require the IP address of the target Jetson device, which can either be provided as a command-line argument or sourced from a `device_ip` file if present.

## File Structure and Workflow
The scripts are divided into three main categories:
1. **Docker-Based Scripts** (`docker_` prefix): These scripts perform actions such as compiling and deploying Jetson kernels within a Docker container. The container provides a controlled environment with all dependencies, making the build process more reliable.
2. **Host-Based Scripts** (`host_` prefix): These scripts perform actions directly on the host machine without using Docker.
3. **Jetson Device Scripts** (`jetson_` prefix): These scripts interact directly with the Jetson device, performing operations such as installing tools, deploying kernels, or debugging.

Each script is crafted to target specific parts of the workflow, from configuration (`menuconfig_jetson_kernel.sh`) to building (`compile_jetson_kernel.sh`) to deploying (`deploy_only_jetson.sh`). Using the scripts in combination allows for efficient management of the kernel lifecycle.

## Tips for Usage
- **Device IP and Username**: The scripts can optionally use a `device_ip` or `device_username` file to store the target device's information. If present, this avoids the need to provide these details on every script invocation.
- **Default Values**: Many scripts come with default values for parameters such as the toolchain and kernel name. These values can be overridden via command-line arguments if needed.
- **Safety and Testing**: It is recommended to use the `dry-run` option where applicable to test the commands without executing them on the target device. This can help prevent unintentional changes.


