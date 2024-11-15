#!/usr/bin/env python3

import argparse
import os
import subprocess
from utils.docker_utils import build_docker_image, inspect_docker_image, cleanup_docker
from utils.clone_utils import clone_kernel, clone_toolchain, clone_overlays, clone_device_tree

def locate_target_modules(kernel_name):
    # Locate target modules based on their `.c` files.
    kernels_dir = os.path.join("kernels")
    kernel_source_path = os.path.join(kernels_dir, kernel_name, "kernel")

    target_modules_file = os.path.join("target_modules.txt")
    if not os.path.exists(target_modules_file):
        raise FileNotFoundError("Error: target_modules.txt not found. Please create the file with the list of modules to build.")

    with open(target_modules_file, 'r') as file:
        target_modules = [line.strip() for line in file if line.strip()]

    if not target_modules:
        raise ValueError("Error: No target modules specified in target_modules.txt.")

    # Dictionary to store module directories and the modules they contain
    module_locations = {}

    # Find the module paths based on directories containing `.c` files
    for module in target_modules:
        find_command = f"find {kernel_source_path} -type f -name {module}.c"
        try:
            find_output = subprocess.check_output(find_command, shell=True, universal_newlines=True).strip()
            if find_output:
                found_path = find_output.splitlines()[0]
                module_dir = os.path.dirname(found_path)

                # Convert the found path to a relative path from the kernel root
                kernel_root = os.path.join(kernels_dir, kernel_name, "kernel", "kernel")
                relative_module_dir = os.path.relpath(module_dir, kernel_root)

                if relative_module_dir not in module_locations:
                    module_locations[relative_module_dir] = {
                        "modules": []
                    }

                module_locations[relative_module_dir]["modules"].append(module)

        except subprocess.CalledProcessError:
            print(f"Warning: Could not locate source file for module {module}. Make sure {module}.c exists in the source.")

    return module_locations


def compile_target_modules_host(kernel_name, arch, toolchain_name=None, localversion=None, dry_run=False):
    module_locations = locate_target_modules(kernel_name)

    if not module_locations:
        print("No modules to compile.")
        return

    # Base command for invoking make on the host system
    kernels_dir = os.path.join("kernels")
    kernel_dir = os.path.join(kernels_dir, kernel_name, "kernel", "kernel")
    base_command = f"make -C {kernel_dir} ARCH={arch}"

    if toolchain_name:
        # Get the absolute path for the cross compiler
        toolchain_bin_path = os.path.abspath(os.path.join('toolchains', toolchain_name, 'bin', toolchain_name))
        base_command += f" CROSS_COMPILE={toolchain_bin_path}-"

    if localversion:
        base_command += f" LOCALVERSION={localversion}"

    # Run make for each unique module directory located earlier
    for module_dir_relative, modules in module_locations.items():
        module_command = f"{base_command} M={module_dir_relative} modules"
        if dry_run:
            print(f"[Dry-run] Would run command: {module_command} for modules: {', '.join(modules)}")
        else:
            print(f"Running command: {module_command} for modules: {', '.join(modules)}")
            subprocess.Popen(module_command, shell=True).wait()


def compile_target_modules_docker(kernel_name, arch, toolchain_name=None, localversion=None, dry_run=False):
    # Compiles targeted kernel modules using Docker for encapsulation.
    kernels_dir = os.path.join("kernels")
    toolchains_dir = os.path.join("toolchains")

    # Create Docker volume arguments to mount kernel, toolchain, and overlays directories into a builder working directory
    kernels_dir_abs = os.path.abspath(kernels_dir)
    toolchains_dir_abs = os.path.abspath(toolchains_dir)
    volume_args = ["-v", f"{kernels_dir_abs}:/builder/kernels", "-v", f"{toolchains_dir_abs}:/builder/toolchains"]

    # Get current user ID and group ID to run Docker commands as the current user
    user_id = os.getuid()
    group_id = os.getgid()

    # Get total number of CPUs on the machine
    total_cpus = os.cpu_count()

    # Construct the Docker command
    docker_command = [
        "docker", "run", "--rm", "-it", "-u", f"{user_id}:{group_id}",
        "--cpus=" + str(total_cpus)
    ] + volume_args + [
        "-w", f"/builder/kernels/{kernel_name}/kernel/kernel", "kernel_builder", "/bin/bash", "-c"
    ]

    # Base command for invoking make
    base_command = f"make ARCH={arch} -j{total_cpus if total_cpus else '$(nproc)'}"

    if toolchain_name:
        base_command += f" CROSS_COMPILE=/builder/toolchains/{toolchain_name}/bin/{toolchain_name}-"

    if localversion:
        base_command += f" LOCALVERSION={localversion}"

    env = os.environ.copy()
    if toolchain_name:
        env["PATH"] = f"/builder/toolchains/{toolchain_name}/bin:" + env["PATH"]

    # Locate module directories
    module_locations = locate_target_modules(kernel_name)

    if not module_locations:
        print("No modules to compile.")
        return

    # Add the configuration steps (make oldconfig, make prepare, and make modules_prepare) before building modules
    config_commands = f"{base_command} oldconfig && {base_command} prepare && {base_command} modules_prepare"

    # Create commands to build each directory (if not empty)
    combined_command = f"{config_commands} && "  # Ensure configuration runs first
    for module_dir_relative, modules in module_locations.items():
        combined_command += f"{base_command} M={module_dir_relative} modules && "

    # Remove trailing "&&" if present
    combined_command = combined_command.rstrip("&& ")

    # Run the combined command in Docker
    if dry_run:
        print(f"[Dry-run] Would run Docker command: {' '.join(docker_command + [combined_command])}")
    else:
        full_command = docker_command + [combined_command]
        print(f"Running Docker command: {' '.join(full_command)}")
        subprocess.Popen(full_command, env=env).wait()

def compile_kernel_host(kernel_name, arch, toolchain_name=None, config=None, generate_ctags=False, build_target=None, threads=None, clean=True, use_current_config=False, localversion=None, dtb_paths=None, dry_run=False):
    # Compiles the kernel directly on the host system.
    kernels_dir = os.path.join("kernels")
    kernel_dir = os.path.join(kernels_dir, kernel_name, "kernel", "kernel")

    # Base command for invoking make
    base_command = f"make -C {kernel_dir} ARCH={arch} -j{threads if threads else '$(nproc)'}"

    if toolchain_name:
        base_command += f" CROSS_COMPILE={os.path.join('toolchains', toolchain_name, 'bin', toolchain_name)}-"

    if localversion:
        base_command += f" LOCALVERSION={localversion}"

    # If use_current_config is specified, get the current kernel config and place it in the kernel directory
    if use_current_config:
        current_config_path = os.path.join(kernel_dir, ".config")
        zcat_command = f"zcat /proc/config.gz > {current_config_path}"
        print(f"Fetching current kernel config: {zcat_command}")
        if not dry_run:
            subprocess.run(zcat_command, shell=True, check=True)

    # Combine mrproper (if enabled), configuration, and kernel compilation into a single command
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
                combined_command += f"{base_command} modules_install INSTALL_MOD_PATH=../modules && "
                combined_command += f"mkdir -p ../modules/boot && "
                combined_command += f"cp {kernel_dir}/arch/{arch}/boot/Image ../modules/boot/Image.{localversion} && "
                if dtb_paths:
                    for dtb in dtb_paths:
                        combined_command += f"cp {dtb} ../modules/boot/ && "
            elif target == "modules":
                combined_command += f"{base_command} modules && "
                combined_command += f"{base_command} modules_install INSTALL_MOD_PATH=../modules && "
            else:
                # General case for any target, including menuconfig
                combined_command += f"{base_command} {target} && "
    else:
        # If no specific target is provided, build the kernel and copy the Image
        combined_command += f"{base_command} && "
        combined_command += f"{base_command} modules_install INSTALL_MOD_PATH=../modules && "
        combined_command += f"mkdir -p ../modules/boot && "
        combined_command += f"cp {kernel_dir}/arch/{arch}/boot/Image ../modules/boot/Image.{localversion}"
        if dtb_paths:
            for dtb in dtb_paths:
                combined_command += f" && cp {dtb} ../modules/boot/"

    # Remove any trailing '&&'
    combined_command = combined_command.rstrip(' &&')

    # Adjust permissions before running ctags to avoid permission issues
    if generate_ctags:
        combined_command += f" && chmod -R u+w {kernel_dir} && ctags -R -f ../tags {kernel_dir}"

    # Run the combined command directly on the host
    if dry_run:
        print(f"[Dry-run] Would run combined command: {combined_command}")
    else:
        print(f"Running combined command: {combined_command}")
        subprocess.Popen(combined_command, shell=True).wait()


def compile_kernel_docker(kernel_name, arch, toolchain_name=None, rpi_model=None, config=None, generate_ctags=False, build_target=None, threads=None, clean=True, use_current_config=False, localversion=None, dtb_paths=None, dry_run=False):
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

    # Get total number of CPUs on the machine
    total_cpus = os.cpu_count()

    # Construct the Docker command
    docker_command = [
        "docker", "run", "--rm", "-it", "--init", "-u", f"{user_id}:{group_id}",
        "--cpus=" + str(total_cpus)
    ] + volume_args + [
        "-w", "/builder", "kernel_builder", "/bin/bash", "-c"
    ]

    # Base command for invoking make
    base_command = f"make -C /builder/kernels/{kernel_name}/kernel/kernel ARCH={arch} -j{threads if threads else '$(nproc)'}"

    if toolchain_name:
        base_command += f" CROSS_COMPILE=/builder/toolchains/{toolchain_name}/bin/{toolchain_name}-"

    if localversion:
        base_command += f" LOCALVERSION={localversion}"

    env = os.environ.copy()
    if toolchain_name:
        env["PATH"] = f"/builder/toolchains/{toolchain_name}/bin:" + env["PATH"]

    # If use_current_config is specified, get the current kernel config and place it in the kernel directory
    if use_current_config:
        current_config_path = f"/builder/kernels/{kernel_name}/kernel/kernel/.config"
        zcat_command = f"zcat /proc/config.gz > {current_config_path}"
        print(f"Fetching current kernel config: {zcat_command}")
        if not dry_run:
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
                combined_command += f"mkdir -p /builder/kernels/{kernel_name}/modules/boot && "
                combined_command += f"cp /builder/kernels/{kernel_name}/kernel/kernel/arch/{arch}/boot/Image /builder/kernels/{kernel_name}/modules/boot/Image.{localversion} && "
                if dtb_paths:
                    for dtb in dtb_paths:
                        combined_command += f"cp {dtb} /builder/kernels/{kernel_name}/modules/boot/ && "
            elif target == "modules":
                combined_command += f"{base_command} modules && "
                combined_command += f"{base_command} modules_install INSTALL_MOD_PATH=/builder/kernels/{kernel_name}/modules && "
            else:
                # General case for any target, including menuconfig
                combined_command += f"{base_command} {target} && "
    else:
        # If no specific target is provided, build the kernel and copy the Image
        combined_command += f"{base_command} && "
        combined_command += f"{base_command} modules_install INSTALL_MOD_PATH=/builder/kernels/{kernel_name}/modules && "
        combined_command += f"mkdir -p /builder/kernels/{kernel_name}/modules/boot && "
        combined_command += f"cp /builder/kernels/{kernel_name}/kernel/kernel/arch/{arch}/boot/Image /builder/kernels/{kernel_name}/modules/boot/Image.{localversion}"
        if dtb_paths:
            for dtb in dtb_paths:
                combined_command += f" && cp {dtb} /builder/kernels/{kernel_name}/modules/boot/"

    # Remove any trailing '&&'
    combined_command = combined_command.rstrip(' &&')

    # Adjust permissions before running ctags to avoid permission issues
    if generate_ctags:
        combined_command += f" && chmod -R u+w /builder/kernels/{kernel_name}/kernel && ctags -R -f /builder/tags /builder/kernels/{kernel_name}/kernel"

    # Run the combined command in a single Docker container session to ensure files are preserved
    if dry_run:
        print(f"[Dry-run] Would run combined command: {' '.join(docker_command + [combined_command])}")
    else:
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
    compile_parser.add_argument("--localversion", help="Set a local version string to append to the kernel version")
    compile_parser.add_argument("--dtb-paths", nargs='+', help="Paths to the DTB files to copy alongside the kernel image")
    compile_parser.add_argument("--host-build", action="store_true", help="Compile the kernel directly on the host instead of using Docker")
    compile_parser.add_argument("--dry-run", action="store_true", help="Print the commands without executing them")

    target_modules_parser = subparsers.add_parser("compile-target-modules")
    target_modules_parser.add_argument("--kernel-name", required=True, help="Name of the kernel subfolder to use for targeted module compilation")
    target_modules_parser.add_argument("--arch", required=True, help="Target architecture (e.g., arm64 for Jetson)")
    target_modules_parser.add_argument("--toolchain-name", help="Name of the toolchain to use for cross-compiling")
    target_modules_parser.add_argument("--localversion", help="Set a local version string to append to the kernel version")
    target_modules_parser.add_argument("--host-build", action="store_true", help="Compile the kernel directly on the host instead of using Docker")
    target_modules_parser.add_argument("--dry-run", action="store_true", help="Print the commands without executing them")

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
        if args.host_build:
            compile_kernel_host(
                kernel_name=args.kernel_name,
                arch=args.arch,
                toolchain_name=args.toolchain_name,
                config=args.config,
                generate_ctags=args.generate_ctags,
                build_target=args.build_target,
                threads=args.threads,
                clean=args.clean,
                use_current_config=args.use_current_config,
                localversion=args.localversion,
                dtb_paths=args.dtb_paths,
                dry_run=args.dry_run
            )
        else:
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
                use_current_config=args.use_current_config,
                localversion=args.localversion,
                dtb_paths=args.dtb_paths,
                dry_run=args.dry_run
            )
    elif args.command == "compile-target-modules":
        if args.host_build:
            compile_target_modules_host(
                kernel_name=args.kernel_name,
                arch=args.arch,
                toolchain_name=args.toolchain_name,
                localversion=args.localversion,
                dry_run=args.dry_run
            )
        else:
            compile_target_modules_docker(
                kernel_name=args.kernel_name,
                arch=args.arch,
                toolchain_name=args.toolchain_name,
                localversion=args.localversion,
                dry_run=args.dry_run
            )
    elif args.command == "inspect":
        inspect_docker_image()
    elif args.command == "cleanup":
        cleanup_docker()

if __name__ == "__main__":
    main()

