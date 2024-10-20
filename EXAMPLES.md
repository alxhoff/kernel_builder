# Kernel Builder Example Workflows

This document contains examples of workflows for using the kernel builder and deployer for different platforms: x86 host machines, NVIDIA Jetson boards, and Raspberry Pi.

## Example Workflows

### x86 Host Machine Workflow

1. **Build the Docker Image**:
   ```bash
   python3 kernel_builder.py build
   ```

2. **Clone the Kernel Source**:
   ```bash
   python3 kernel_builder.py clone-kernel --kernel-source-url https://github.com/torvalds/linux.git --kernel-name x86
   ```

3. **Compile the Kernel for x86**:
   ```bash
   python3 kernel_builder.py compile --kernel-name x86 --arch x86_64 --config defconfig --build-target kernel,modules --threads 4
   ```

4. **Deploy to x86 Host Machine**:
   ```bash
   python3 kernel_deployer.py deploy-x86
   ```

### NVIDIA Jetson (ARM64) Workflow

1. **Build the Docker Image**:
   ```bash
   python3 kernel_builder.py build
   ```

2. **Clone the Kernel Source**:
   ```bash
   python3 kernel_builder.py clone-kernel --kernel-source-url https://github.com/alxhoff/jetson-kernel --kernel-name jetson --git-tag sensing_world_v1
   ```

3. **Clone the Toolchain**:
   ```bash
   python3 kernel_builder.py clone-toolchain --toolchain-url https://github.com/alxhoff/Jetson-Linux-Toolchain --toolchain-name aarch64-buildroot-linux-gnu --git-tag sensing_world_v1
   ```

4. **Clone Overlays (Optional)**:
   ```bash
   python3 kernel_builder.py clone-overlays --overlays-url https://github.com/alxhoff/jetson-kernel-overlays --kernel-name jetson
   ```

5. **Clone Device Tree Hardware Repository (Optional)**:
   ```bash
   python3 kernel_builder.py clone-device-tree --device-tree-url https://github.com/alxhoff/jetson-device-tree-hardware --kernel-name jetson --git-tag sensing_world_v1
   ```

6. **Compile the Kernel for Jetson (ARM64)**:
   ```bash
   python3 kernel_builder.py compile --kernel-name jetson --arch arm64 --toolchain-name aarch64-buildroot-linux-gnu --config tegra_defconfig --generate-ctags --build-target kernel,dtbs,modules --threads 4
   ```
   > **Note**: The compilation now runs inside a Docker container. The kernel and toolchain directories are mounted into `/builder` to ensure consistency.

7. **Deploy to NVIDIA Jetson Board**:
   ```bash
   python3 kernel_deployer.py deploy-device --kernel-name jetson --ip 192.168.1.10 --user ubuntu --dry-run
   ```

### Raspberry Pi Workflow

1. **Build the Docker Image**:
   ```bash
   python3 kernel_builder.py build
   ```

2. **Clone the Kernel Source**:
   ```bash
   python3 kernel_builder.py clone-kernel --kernel-source-url https://github.com/raspberrypi/linux.git --kernel-name rpi --git-tag rpi-5.10.y
   ```

3. **Compile the Kernel for Raspberry Pi**:
   ```bash
   python3 kernel_builder.py compile --kernel-name rpi --arch arm --toolchain-name arm-buildroot-linux-gnueabihf --rpi-model rpi4 --config bcm2711_defconfig --generate-ctags --build-target kernel,dtbs,modules --threads 4
   ```
   > **Note**: Like other workflows, the compilation runs inside a Docker container, with necessary directories mounted under `/builder`.

4. **Deploy to Raspberry Pi**:
   ```bash
   python3 kernel_deployer.py deploy-device --kernel-name rpi --ip 192.168.1.15 --user pi --dry-run
   ```

### Inspecting the Docker Image

If you need to inspect the Docker image for troubleshooting or to verify the build environment, you can open a bash shell inside the Docker container using the following command:

**Command**:
```bash
python3 kernel_builder.py inspect
```

This command will open an interactive bash shell within the Docker container, mounting the kernel and toolchain directories into `/builder`. This allows you to inspect the contents and verify the build environment.

This command will open an interactive bash shell within the Docker container, mounting the kernel and toolchain directories into `/builder`. This allows you to inspect the contents and verify the build environment.

### Cleaning Up Docker Resources

To clean up the Docker image and remove any unused containers, you can use the `cleanup` command.

**Command**:
```bash
python3 kernel_builder.py cleanup
```

This will remove the Docker image named `kernel_builder` and prune unused containers, helping to free up system resources.

## Notes

- The kernel compilation process for all workflows now runs entirely inside a Docker container to ensure a consistent environment across different platforms.
- All necessary directories (kernel source, toolchain) are mounted into Docker as volumes under `/builder` to ensure consistent paths within the container.
- The Docker encapsulation helps in avoiding environment-related issues and ensures that the compilation environment is identical regardless of the host machine.


