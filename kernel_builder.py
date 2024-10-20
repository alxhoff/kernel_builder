import os
import argparse
import subprocess
import logging

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Function to build Docker image
def build_docker_image(rebuild=False):
    logging.info("Building Docker image for cross-compiling kernels...")

    # Build the Docker image
    build_command = [
        "docker", "build",
        "-t", "kernel-build-env",
        "."
    ]

    if rebuild:
        build_command.insert(2, "--no-cache")

    subprocess.run(build_command, check=True)
    logging.info("Docker image built successfully.")

# Function to check cross-compiler installation
def check_cross_compiler(arch, rpi_model=None):
    cross_compile = get_cross_compile_prefix(arch, rpi_model)
    compiler_command = cross_compile.rstrip('-')
    if subprocess.run(["which", compiler_command], capture_output=True).returncode != 0:
        raise EnvironmentError(f"Cross-compiler {compiler_command} not found. Please install it before proceeding.")

# Function to clone kernel source
def clone_kernel(kernel_source_url, kernel_dir, git_tag="master"):
    if os.path.exists(kernel_dir):
        logging.info(f"Kernel directory {kernel_dir} already exists. Checking if the correct tag is checked out...")
        # Check if the correct tag is checked out
        current_tag = subprocess.run(["git", "-C", kernel_dir, "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True).stdout.strip()
        if current_tag != git_tag:
            logging.info(f"Current tag is {current_tag}. Checking out the correct tag {git_tag}...")
            subprocess.run(["git", "-C", kernel_dir, "fetch", "--all"], check=True)
            subprocess.run(["git", "-C", kernel_dir, "checkout", git_tag], check=True)
            logging.info(f"Checked out to the correct tag {git_tag}.")
        else:
            logging.info(f"Kernel directory is already checked out to the correct tag {git_tag}.")
    else:
        logging.info(f"Cloning kernel from {kernel_source_url} into {kernel_dir} with tag {git_tag}...")
        os.makedirs(kernel_dir, exist_ok=True)
        subprocess.run(["git", "clone", kernel_source_url, kernel_dir], check=True)
        subprocess.run(["git", "-C", kernel_dir, "checkout", git_tag], check=True)
        logging.info("Kernel cloned successfully.")

# Function to compile the kernel in the Docker container
def compile_kernel(output_dir, kernel_dir, arch, cross_compile, dtb_dir=None, rpi_model=None):
    logging.info(f"Compiling kernel from {kernel_dir} for architecture: {arch} with cross-compiler: {cross_compile}")

    # Add an optional device tree build step if provided
    device_tree_command = ""
    if dtb_dir:
        device_tree_command = f"&& make ARCH={arch} CROSS_COMPILE={cross_compile} dtbs && cp arch/{arch}/boot/dts/*.dtb /output/{arch}"

    # Additional Raspberry Pi configuration
    rpi_make_command = ""
    if rpi_model:
        if rpi_model == "rpi3":
            rpi_make_command = "bcm2709_defconfig"
        elif rpi_model == "rpi4":
            rpi_make_command = "bcm2711_defconfig"
        else:
            raise ValueError(f"Unsupported Raspberry Pi model: {rpi_model}")
        rpi_make_command = f"make ARCH={arch} CROSS_COMPILE={cross_compile} {rpi_make_command} && "

    # Run the Docker container and compile the kernel
    command = build_docker_run_command(output_dir, kernel_dir, arch, cross_compile, rpi_make_command, device_tree_command)

    subprocess.run(command, check=True)
    logging.info("Kernel compilation completed successfully.")

# Function to construct Docker run command for kernel compilation
def build_docker_run_command(output_dir, kernel_dir, arch, cross_compile, rpi_make_command, device_tree_command):
    return [
        "docker", "run", "-it", "--rm",
        "-v", f"{output_dir}:/output",  # Mount output directory to store the compiled files
        "-v", f"{kernel_dir}:/kernel",  # Mount specific kernel directory to reflect changes inside the container
        "kernel-build-env",
        "bash", "-c",
        f"cd /kernel && {rpi_make_command}make -j$(nproc) ARCH={arch} CROSS_COMPILE={cross_compile} && "
        f"make ARCH={arch} CROSS_COMPILE={cross_compile} modules && "
        f"make ARCH={arch} CROSS_COMPILE={cross_compile} INSTALL_MOD_PATH=/output/{arch} modules_install && "
        f"cp arch/{arch}/boot/Image /output/{arch} {device_tree_command}"
    ]

# Function to determine cross-compiler prefix based on architecture and Raspberry Pi model
def get_cross_compile_prefix(arch, rpi_model=None):
    if rpi_model:
        return "arm-linux-gnueabihf-"
    if arch == "arm64":
        return "aarch64-linux-gnu-"
    elif arch == "x86_64":
        return "x86_64-linux-gnu-"
    else:
        raise ValueError(f"Unsupported architecture: {arch}")

# Function to open a bash shell inside the Docker container for inspection
def inspect_container(output_dir):
    logging.info("Opening a bash shell in the Docker container...")

    # Run the Docker container interactively with bash
    command = [
        "docker", "run", "-it", "--rm",
        "-v", f"{output_dir}:/output",  # Mount output directory to inspect files
        "kernel-build-env",
        "/bin/bash"
    ]

    subprocess.run(command, check=True)

# Function to clean up Docker images and containers
def cleanup_docker():
    logging.info("Cleaning up Docker images and containers...")

    # Remove the Docker image
    subprocess.run(["docker", "rmi", "-f", "kernel-build-env"], check=False)

    # Prune any dangling Docker volumes or containers
    subprocess.run(["docker", "system", "prune", "-f"], check=False)
    logging.info("Docker images and containers cleaned up.")

# Main function
def main():
    parser = argparse.ArgumentParser(
        description="Kernel Builder for cross-compiling NVIDIA Jetson, x86, and Raspberry Pi kernels using Docker",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )

    subparsers = parser.add_subparsers(dest="command", help="Available commands to build Docker image, compile the kernel, or inspect the container")

    # Sub-command for building Docker image
    build_parser = subparsers.add_parser(
        "build",
        help="Build the Docker image used for cross-compiling the kernel",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    build_parser.add_argument(
        "--rebuild", action="store_true",
        help="Rebuild the Docker image from scratch (no cache)"
    )

    # Sub-command for cloning kernel source
    clone_parser = subparsers.add_parser(
        "clone-kernel",
        help="Clone the kernel source code",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    clone_parser.add_argument(
        "--kernel-source-url",
        required=True,
        help="URL of the kernel source to be cloned"
    )
    clone_parser.add_argument(
        "--kernel-dir",
        required=True,
        help="Directory where the kernel source will be cloned"
    )
    clone_parser.add_argument(
        "--git-tag",
        default="master",
        help="Git tag to check out after cloning (default: master)"
    )

    # Sub-command for compiling the kernel
    compile_parser = subparsers.add_parser(
        "compile",
        help="Compile the kernel using the Docker environment",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    compile_parser.add_argument(
        "--output-dir",
        required=True,
        help="Directory on the host where the compiled kernel and modules will be stored"
    )
    compile_parser.add_argument(
        "--kernel-dir",
        required=True,
        help="Directory on the host where the kernel source is located"
    )
    compile_parser.add_argument(
        "--arch",
        default="arm64",
        help="Target architecture (e.g., arm64 for NVIDIA Jetson boards)"
    )
    compile_parser.add_argument(
        "--cross-compile",
        help="Cross compiler prefix (e.g., aarch64-linux-gnu- for ARM64). If not provided, it will be determined automatically based on the architecture or Raspberry Pi model"
    )
    compile_parser.add_argument(
        "--device-tree",
        help="Path to store device tree files after compilation"
    )
    compile_parser.add_argument(
        "--rpi-model",
        choices=["rpi3", "rpi4"],
        help="Specify the Raspberry Pi model to compile the kernel for (e.g., rpi3 or rpi4)"
    )

    # Sub-command for inspecting the Docker container
    inspect_parser = subparsers.add_parser(
        "inspect",
        help="Open a bash shell inside the Docker container to inspect the current state and filesystem",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    inspect_parser.add_argument(
        "--output-dir",
        required=True,
        help="Directory on the host to mount in the Docker container for inspection"
    )

    # Sub-command for cleaning up Docker images and containers
    cleanup_parser = subparsers.add_parser(
        "cleanup",
        help="Clean up the Docker image and container so that it can be rebuilt",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )

    # Parse arguments
    args = parser.parse_args()

    if args.command == "build":
        # Build Docker image
        build_docker_image(args.rebuild)
    elif args.command == "clone-kernel":
        # Clone kernel source
        clone_kernel(args.kernel_source_url, args.kernel_dir, args.git_tag)
    elif args.command == "compile":
        # Determine cross-compile prefix if not provided
        cross_compile = args.cross_compile or get_cross_compile_prefix(args.arch, args.rpi_model)
        # Compile the kernel
        compile_kernel(args.output_dir, args.kernel_dir, args.arch, cross_compile, args.device_tree, args.rpi_model)
    elif args.command == "inspect":
        # Inspect the Docker container by opening a bash shell
        inspect_container(args.output_dir)
    elif args.command == "cleanup":
        # Clean up Docker images and containers
        cleanup_docker()
    else:
        parser.print_help()

if __name__ == "__main__":
    main()

