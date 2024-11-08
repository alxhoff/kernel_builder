#!/usr/bin/env python3

import argparse
import os
import subprocess
from docker_utils import build_docker_image, inspect_docker_image, cleanup_docker
from clone_utils import clone_kernel, clone_toolchain, clone_overlays, clone_device_tree

def compile_kernel_docker(kernel_name, arch, toolchain_name=None, rpi_model=None, config=None, generate_ctags=False, build_target=None, threads=None, clean=True, use_current_config=False):
    # Compiles the kernel using Docker for encapsulation.
    kernels_dir = os.path.join("kernels")
    toolchains_dir = os.path.join("toolchains")

    # Create Docker volume arguments to mount kernel, toolchain, and overlays directories into a builder working directory
    kernels_dir_abs = os.path.abspath(kernels_dir)
    toolchains_dir_abs = os.path.abspath(toolchains_dir)
    volume_args = ["-v", f"{kernels_dir_abs}:/builder/kernels", "-v", f"{toolchains_dir_abs}:/builder/toolchains"]

    # Get current user ID and group ID to run Docker commands as the current user
    user_id = os.getuid()
    group_id = os.getgid()

    # Construct the Docker command
    docker_command = [
        "docker", "run", "--rm", "-it", "-u", f"{user_id}:{group_id}"
    ] + volume_args + [
        "-w", "/builder", "kernel_builder", "/bin/bash", "-c"
    ]

    # Base command for invoking make
    base_command = f"make -C /builder/kernels/{kernel_name}/kernel/kernel ARCH={arch} -j{threads if threads else '$(nproc)'}"

    if toolchain_name:
        base_command += f" CROSS_COMPILE=/builder/toolchains/{toolchain_name}/bin/{toolchain_name}-"

    env = os.environ.copy()
    if toolchain_name:
        env["PATH"] = f"/builder/toolchains/{toolchain_name}/bin:" + env["PATH"]

    # If use_current_config is specified, get the current kernel config and place it in the kernel directory
    if use_current_config:
        current_config_path = f"/builder/kernels/{kernel_name}/kernel/kernel/.config"
        zcat_command = f"zcat /proc/config.gz > {current_config_path}"
        print(f"Fetching current kernel config: {zcat_command}")
        subprocess.run(zcat_command, shell=True, check=True)

    # Combine mrproper (if enabled), configuration, and kernel compilation into a single Docker run command
    combined_command = ""
    if clean:
        combined_command += f"{base_command} mrproper && "
    if config or use_current_config:
        combined_command += f"{base_command} {config or 'oldconfig'} && "

    if build_target:
        targets = build_target.split(',')
        for target in targets:
            if target == "kernel":
                combined_command += f"{base_command} && "
                combined_command += f"{base_command} modules_install INSTALL_MOD_PATH=/builder/kernels/{kernel_name}/modules && "
            elif target == "modules":
                combined_command += f"{base_command} modules && "
                combined_command += f"{base_command} modules_install INSTALL_MOD_PATH=/builder/kernels/{kernel_name}/modules && "
            else:
                # General case for any target, including menuconfig
                combined_command += f"{base_command} {target} && "
    else:
        # If no specific target is provided, build the kernel
        combined_command += f"{base_command} && "
        combined_command += f"{base_command} modules_install INSTALL_MOD_PATH=/builder/kernels/{kernel_name}/modules"

    # Remove any trailing '&&'
    combined_command = combined_command.rstrip(' &&')

    # Adjust permissions before running ctags to avoid permission issues
    if generate_ctags:
        combined_command += f" && chmod -R u+w /builder/kernels/{kernel_name}/kernel && ctags -R -f /builder/tags /builder/kernels/{kernel_name}/kernel"

    # Run the combined command in a single Docker container session to ensure files are preserved
    full_command = docker_command + [combined_command]
    print(f"Running combined command: {' '.join(full_command)}")
    subprocess.Popen(full_command, env=env).wait()

def main():
    parser = argparse.ArgumentParser(description="Kernel Builder Script")
    subparsers = parser.add_subparsers(dest="command")

    # Build Docker image command
    build_parser = subparsers.add_parser("build")
    build_parser.add_argument("--rebuild", action="store_true", help="Rebuild the Docker image without using the cache")

    # Clone kernel command
    clone_parser = subparsers.add_parser("clone-kernel")
    clone_parser.add_argument("--kernel-source-url", required=True, help="URL of the kernel source to be cloned")
    clone_parser.add_argument("--kernel-name", required=True, help="Name for the kernel subfolder")
    clone_parser.add_argument("--git-tag", help="Git tag to check out after cloning the kernel source")

    # Clone toolchain command
    clone_toolchain_parser = subparsers.add_parser("clone-toolchain")
    clone_toolchain_parser.add_argument("--toolchain-url", required=True, help="URL of the toolchain to be cloned")
    clone_toolchain_parser.add_argument("--toolchain-name", required=True, help="Name for the toolchain subfolder")
    clone_toolchain_parser.add_argument("--git-tag", help="Git tag to check out after cloning the toolchain")

    # Clone overlays command
    clone_overlays_parser = subparsers.add_parser("clone-overlays")
    clone_overlays_parser.add_argument("--overlays-url", required=True, help="URL of the overlays repository to be cloned")
    clone_overlays_parser.add_argument("--kernel-name", required=True, help="Name of the kernel subfolder where overlays will be added")
    clone_overlays_parser.add_argument("--git-tag", help="Git tag to check out after cloning the overlays")

    # Clone device tree command
    clone_device_tree_parser = subparsers.add_parser("clone-device-tree")
    clone_device_tree_parser.add_argument("--device-tree-url", required=True, help="URL of the device tree hardware repository to be cloned")
    clone_device_tree_parser.add_argument("--kernel-name", required=True, help="Name of the kernel subfolder where device tree will be added")
    clone_device_tree_parser.add_argument("--git-tag", help="Git tag to check out after cloning the device tree")

    # Compile kernel command
    compile_parser = subparsers.add_parser("compile")
    compile_parser.add_argument("--kernel-name", required=True, help="Name of the kernel subfolder to use for compilation")
    compile_parser.add_argument("--arch", required=True, help="Target architecture (e.g., arm64 for Jetson)")
    compile_parser.add_argument("--toolchain-name", help="Name of the toolchain to use for cross-compiling")
    compile_parser.add_argument("--rpi-model", help="Specify the Raspberry Pi model to compile the kernel for (e.g., rpi3 or rpi4)")
    compile_parser.add_argument("--config", help="Kernel configuration to use for compilation (e.g., defconfig, tegra_defconfig)")
    compile_parser.add_argument("--generate-ctags", action="store_true", help="Generate ctags/tags file for the kernel source")
    compile_parser.add_argument("--build-target", help="Comma-separated list of build targets (e.g., kernel,dtbs,modules,bindeb-pkg). If 'kernel' is specified, it will directly call make without a target.")
    compile_parser.add_argument("--threads", type=int, help="Number of threads to use for compilation (default: use all available cores)")
    compile_parser.add_argument("--clean", action="store_true", help="Run mrproper to clean the kernel build directory before building")
    compile_parser.add_argument("--use-current-config", action="store_true", help="Use the current system kernel configuration for building the kernel")

    # Inspect Docker image command
    inspect_parser = subparsers.add_parser("inspect")

    # Cleanup Docker command
    cleanup_parser = subparsers.add_parser("cleanup")

    args = parser.parse_args()

    # Print help if no command is provided
    if not args.command:
        parser.print_help()
        exit(1)

    if args.command == "build":
        build_docker_image(rebuild=args.rebuild)
    elif args.command == "clone-kernel":
        clone_kernel(kernel_source_url=args.kernel_source_url, kernel_name=args.kernel_name, git_tag=args.git_tag)
    elif args.command == "clone-toolchain":
        clone_toolchain(toolchain_url=args.toolchain_url, toolchain_name=args.toolchain_name, git_tag=args.git_tag)
    elif args.command == "clone-overlays":
        clone_overlays(overlays_url=args.overlays_url, kernel_name=args.kernel_name, git_tag=args.git_tag)
    elif args.command == "clone-device-tree":
        clone_device_tree(device_tree_url=args.device_tree_url, kernel_name=args.kernel_name, git_tag=args.git_tag)
    elif args.command == "compile":
        compile_kernel_docker(
            kernel_name=args.kernel_name,
            arch=args.arch,
            toolchain_name=args.toolchain_name,
            rpi_model=args.rpi_model,
            config=args.config,
            generate_ctags=args.generate_ctags,
            build_target=args.build_target,
            threads=args.threads,
            clean=args.clean,
            use_current_config=args.use_current_config
        )
    elif args.command == "inspect":
        inspect_docker_image()
    elif args.command == "cleanup":
        cleanup_docker()

if __name__ == "__main__":
    main()

