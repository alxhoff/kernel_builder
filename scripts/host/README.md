# Kernel Management Scripts

This document provides an overview of the three kernel-related scripts that are used for building, deploying, and managing the targeted kernel modules on a Linux-based host or Jetson platform.

### Scripts Overview

1. **`build_kernel.sh`**
   - **Description**: This script is used to build the Linux kernel for the specified kernel name and toolchain. It allows customization of build targets and supports different architectures.
   - **Usage**:
     ```bash
     ./build_kernel.sh <kernel-name> <toolchain-name> [build-target]
     ```
   - **Arguments**:
     - `<kernel-name>`: The name of the kernel source (e.g., "jetson").
     - `<toolchain-name>`: The toolchain used to cross-compile the kernel (e.g., "aarch64-buildroot-linux-gnu").
     - `[build-target]` (Optional): Specify additional make targets (e.g., "clean").
   - **Defaults**:
     - Kernel name: `jetson`
     - Toolchain: `aarch64-buildroot-linux-gnu`
     - Architecture: `arm64`

2. **`build_kernel_cartken_jetson.sh`**
   - **Description**: This script provides a simplified version of the `build_kernel.sh` script tailored specifically for building the Jetson kernel using the `aarch64-buildroot-linux-gnu` toolchain.
   - **Usage**:
     ```bash
     ./build_kernel_cartken_jetson.sh [build-target]
     ```
   - **Arguments**:
     - `[build-target]` (Optional): Specify additional make targets (e.g., "clean").
   - **Details**: The script automatically passes the default kernel name (`jetson`) and toolchain (`aarch64-buildroot-linux-gnu`) to `build_kernel.sh`. Any additional arguments specified when running the script are passed along as build targets.

3. **`build_targeted_modules.sh`**
   - **Description**: This script builds targeted kernel modules located within a specific subdirectory of the kernel source. This script is helpful for building specific driver modules without re-building the entire kernel.
   - **Usage**:
     ```bash
     ./build_targeted_modules.sh [kernel-name] [toolchain-name] [subdirectory]
     ```
   - **Arguments**:
     - `[kernel-name]` (Optional): The name of the kernel source (default: `jetson`).
     - `[toolchain-name]` (Optional): The name of the toolchain used (default: `aarch64-buildroot-linux-gnu`).
     - `[subdirectory]` (Optional): The path to the target subdirectory inside the kernel source. By default, it builds modules in `nvidia/drivers/media/i2c/`.
   - **Details**: Once the targeted kernel objects (`.ko` files) are built, they are automatically copied to the output directory where the currently installed kernel is stored, located at `kernels/jetson/modules/lib/modules/$KERNEL_VERSION`.
   - **Examples**:
     - To build the `i2c` kernel modules:
       ```bash
       ./build_targeted_modules.sh jetson aarch64-buildroot-linux-gnu nvidia/drivers/media/i2c/
       ```
     - To build modules without specifying kernel name or toolchain:
       ```bash
       ./build_targeted_modules.sh
       ```



