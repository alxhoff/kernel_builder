#!/usr/bin/env python3

import argparse
import os
import subprocess
import sys
from utils.docker_utils import (
    build_docker_image,
    cleanup_docker,
    ensure_docker_image,
    inspect_docker_image,
)
from utils.clone_utils import clone_kernel, clone_toolchain, clone_overlays, clone_device_tree
from utils.kernel_tree import (
    cross_compile_prefix,
    ensure_jp7_toolchain_storage,
    is_nvbuild_kernel,
    jp7_toolchain_defaults,
    locate_nvbuild_dtb,
    nvbuild_image_path,
    nvbuild_incremental_build_commands,
    nvbuild_incremental_ready,
    nvbuild_kernel_out_dir,
    nvbuild_kernel_src_dir,
    nvbuild_kernel_src_subdir,
    nvbuild_localversion_export,
    normalize_localversion_suffix,
    kernel_tree_root,
)


def _host_cross_compile_suffix(toolchain_name: str | None, toolchain_version: str | None) -> str:
    """Absolute CROSS_COMPILE prefix for host builds (make -C kernel uses kernel cwd)."""
    if not toolchain_name or not toolchain_version:
        return ""
    bindir = os.path.abspath(
        os.path.join(
            "storage", "toolchains", toolchain_name, toolchain_version, "bin", toolchain_name
        )
    )
    return f" CROSS_COMPILE={bindir}-"


def locate_dtb_file(kernel_name, dtb_name):
    kernel_subdir = nvbuild_kernel_src_subdir(kernel_name) or "kernel"
    kernel_source_dir = os.path.join("storage", "kernels", kernel_name, "kernel", kernel_subdir)
    legacy_kernel_source_dir = os.path.join("storage", "kernels", kernel_name, "kernel", "kernel")
    top_level_dir = os.path.join("storage", "kernels", kernel_name)
    search_dirs = [kernel_source_dir, legacy_kernel_source_dir, top_level_dir]

    for search_dir in search_dirs:
        # Search for the specified DTB file within the directory
        find_command = f"find {search_dir} -name {dtb_name}"
        print(f"Running DTB search command: {find_command}")
        try:
            find_output = subprocess.check_output(find_command, shell=True, universal_newlines=True).strip()
            if find_output:
                print(f"DTB file found at: {find_output}")
                return find_output.splitlines()[0]  # Return the first match found
        except subprocess.CalledProcessError:
            print(f"Info: DTB file {dtb_name} not found in {search_dir}.")

    nvbuild_dtb = locate_nvbuild_dtb(kernel_name, dtb_name)
    if nvbuild_dtb:
        print(f"DTB file found at: {nvbuild_dtb}")
        return nvbuild_dtb

    print(f"Warning: DTB file {dtb_name} not found in any of the search paths.")
    return None


def _repo_root() -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def _nvbuild_threads(threads) -> str:
    return str(threads) if threads else "$(nproc)"


def _copy_nvbuild_artifacts(kernel_name, arch, localversion, dtb_name, dry_run=False):
    root = kernel_tree_root(kernel_name)
    modules_boot = os.path.join(root, "modules", "boot")
    image_src = nvbuild_image_path(kernel_name)
    image_filename = f"Image.{localversion}" if localversion else "Image"
    commands = [
        f"mkdir -p {modules_boot}",
        f"cp {image_src} {os.path.join(modules_boot, image_filename)}",
    ]
    if dtb_name:
        dtb_path = locate_dtb_file(kernel_name, dtb_name)
        if dtb_path:
            suffix = normalize_localversion_suffix(localversion)
            new_dtb_name = f"{os.path.splitext(dtb_name)[0]}{suffix}.dtb"
            commands.append(f"cp {dtb_path} {os.path.join(modules_boot, new_dtb_name)}")
        else:
            print(f"Warning: DTB file {dtb_name} not found after nvbuild.")
    combined = " && ".join(commands)
    if dry_run:
        print(f"[Dry-run] Would run: {combined}")
        return 0
    print(f"Staging build artifacts: {combined}")
    return subprocess.run(combined, shell=True).returncode


def _nvbuild_append_build_steps(
    parts: list[str],
    *,
    kernel_name: str,
    arch: str,
    kernel_src: str,
    config: str | None,
    build_target: str | None,
    build_modules: bool,
    threads: int | None,
    incremental: bool,
    clean: bool,
) -> None:
    """Extend *parts* with nvbuild full or incremental build commands."""
    if build_target == "menuconfig":
        return
    if build_target == "mrproper":
        return

    oot_only = build_target in ("modules",) or build_modules
    use_incremental = incremental and not clean and nvbuild_incremental_ready(kernel_name)

    if use_incremental:
        print("Incremental build: reusing kernel_out/.config and object files.")
        parts.extend(nvbuild_incremental_build_commands(arch, threads, oot_only=oot_only))
        return

    if incremental and not clean:
        print(
            "Incremental: no kernel_out/.config found — running full nvbuild "
            "(use --no-incremental to force full rebuild when kernel_out exists)."
        )

    if config:
        parts.append(f"make -C {kernel_src} ARCH={arch} {config}")

    if oot_only:
        headers = os.path.join(
            nvbuild_kernel_out_dir(kernel_name),
            "kernel",
            nvbuild_kernel_src_subdir(kernel_name),
        )
        parts.append(f'export KERNEL_HEADERS="{headers}"')
        parts.append("./nvbuild.sh -m")
    else:
        parts.append("./nvbuild.sh")


def compile_nvbuild_kernel_host(
    kernel_name,
    arch,
    toolchain_name=None,
    toolchain_version=None,
    config=None,
    build_target=None,
    threads=None,
    clean=True,
    incremental=True,
    localversion="",
    dtb_name=None,
    build_modules=False,
    dry_run=False,
):
    if not is_nvbuild_kernel(kernel_name):
        raise ValueError(f"{kernel_name} is not an nvbuild kernel tree")

    repo_root = _repo_root()
    ensure_jp7_toolchain_storage(repo_root, dry_run=dry_run)

    if not toolchain_name or not toolchain_version:
        toolchain_name, toolchain_version = jp7_toolchain_defaults()

    root = os.path.abspath(kernel_tree_root(kernel_name))
    kernel_src = nvbuild_kernel_src_dir(kernel_name)
    if not kernel_src:
        print(f"Error: could not find kernel source under {root}/kernel/")
        return 1

    cross = os.path.abspath(
        cross_compile_prefix(toolchain_name, toolchain_version, docker=False)
    )
    if not os.path.isfile(f"{cross}gcc") and not dry_run:
        print(f"Error: JP7 cross compiler not found at {cross}gcc")
        return 1

    parts = [f"cd {root}"]
    parts.append(f'export CROSS_COMPILE="{cross}"')
    lv_export = nvbuild_localversion_export(localversion)
    if lv_export:
        parts.append(lv_export)

    if clean and not build_target:
        parts.append(f"rm -rf {nvbuild_kernel_out_dir(kernel_name)}")

    if build_target == "menuconfig":
        parts.append(
            f"make -C {kernel_src} ARCH={arch} menuconfig"
        )
        combined = " && ".join(parts)
        if dry_run:
            print(f"[Dry-run] Would run: {combined}")
            return 0
        return subprocess.run(combined, shell=True).returncode

    if build_target == "mrproper":
        parts.append(f"rm -rf {nvbuild_kernel_out_dir(kernel_name)}")
        combined = " && ".join(parts)
        if dry_run:
            print(f"[Dry-run] Would run: {combined}")
            return 0
        return subprocess.run(combined, shell=True).returncode

    _nvbuild_append_build_steps(
        parts,
        kernel_name=kernel_name,
        arch=arch,
        kernel_src=kernel_src,
        config=config,
        build_target=build_target,
        build_modules=build_modules,
        threads=threads,
        incremental=incremental,
        clean=clean,
    )

    combined = " && ".join(parts)
    if dry_run:
        print(f"[Dry-run] Would run: {combined}")
        return _copy_nvbuild_artifacts(kernel_name, arch, localversion, dtb_name, dry_run=True)

    print(f"Running nvbuild command: {combined}")
    rc = subprocess.run(combined, shell=True).returncode
    if rc != 0:
        return rc
    return _copy_nvbuild_artifacts(kernel_name, arch, localversion, dtb_name)


def compile_nvbuild_kernel_docker(
    kernel_name,
    arch,
    toolchain_name=None,
    toolchain_version=None,
    config=None,
    build_target=None,
    threads=None,
    clean=True,
    incremental=True,
    localversion="",
    dtb_name=None,
    build_modules=False,
    dry_run=False,
):
    if not is_nvbuild_kernel(kernel_name):
        raise ValueError(f"{kernel_name} is not an nvbuild kernel tree")

    kernels_dir_abs = os.path.abspath(os.path.join("storage", "kernels"))
    toolchains_dir_abs = os.path.abspath(os.path.join("storage", "toolchains"))
    volume_args = [
        "-v", f"{kernels_dir_abs}:/builder/kernels",
        "-v", f"{toolchains_dir_abs}:/builder/toolchains",
    ]

    docker_tty = ["-it"] if (sys.stdin.isatty() and sys.stdout.isatty()) else []
    docker_command_base = [
        "docker", "run", "--rm", *docker_tty, "--init", "-u", "0:0",
        "--cpus=" + str(os.cpu_count()),
    ] + volume_args + [
        "-w", f"/builder/kernels/{kernel_name}",
        "kernel_builder_jp7", "/bin/bash", "-c",
    ]

    if not toolchain_name or not toolchain_version:
        toolchain_name, toolchain_version = jp7_toolchain_defaults()

    cross = cross_compile_prefix(toolchain_name, toolchain_version, docker=True)
    kernel_src_rel = f"kernel/{nvbuild_kernel_src_subdir(kernel_name)}"
    parts = [f'export CROSS_COMPILE="{cross}"']
    lv_export = nvbuild_localversion_export(localversion)
    if lv_export:
        parts.append(lv_export)

    if clean and not build_target:
        parts.append("rm -rf kernel_out")

    if build_target == "menuconfig":
        parts.append(f"make -C {kernel_src_rel} ARCH={arch} menuconfig")
    elif build_target == "mrproper":
        parts.append("rm -rf kernel_out")
    else:
        _nvbuild_append_build_steps(
            parts,
            kernel_name=kernel_name,
            arch=arch,
            kernel_src=kernel_src_rel,
            config=config,
            build_target=build_target,
            build_modules=build_modules,
            threads=threads,
            incremental=incremental,
            clean=clean,
        )

    combined = " && ".join(parts)
    if dry_run:
        print(f"[Dry-run] Would run nvbuild docker: {' '.join(docker_command_base + [combined])}")
        return _copy_nvbuild_artifacts(kernel_name, arch, localversion, dtb_name, dry_run=True)

    print(f"Running Docker nvbuild command: {' '.join(docker_command_base + [combined])}")
    rc = subprocess.Popen(docker_command_base + [combined]).wait()
    if rc != 0:
        return rc
    return _copy_nvbuild_artifacts(kernel_name, arch, localversion, dtb_name)


def _host_kernel_path_to_docker(host_path: str, kernels_dir_abs: str) -> str:
    """Map host path under storage/kernels to /builder/kernels/... (docker -v mount)."""
    if not host_path:
        return host_path
    k_abs = os.path.normpath(os.path.abspath(kernels_dir_abs))
    try:
        p_abs = os.path.normpath(os.path.abspath(host_path))
        if p_abs == k_abs:
            return "/builder/kernels"
        sep = os.sep
        if p_abs.startswith(k_abs + sep):
            rel = p_abs[len(k_abs) + len(sep) :]
            return "/builder/kernels/" + rel.replace("\\", "/")
    except (OSError, ValueError):
        pass
    s = host_path.replace("\\", "/")
    prefix = "storage/kernels/"
    if s.startswith(prefix):
        return "/builder/kernels/" + s[len(prefix) :]
    if s == "storage/kernels":
        return "/builder/kernels"
    return s


def compile_kernel_host(kernel_name, arch, toolchain_name=None, toolchain_version=None, config=None, generate_ctags=False, build_target=None, threads=None, clean=True, incremental=True, use_current_config=False, localversion="", dtb_name=None, build_dtb=False, build_modules=False, overlays=None, dry_run=False):
    if is_nvbuild_kernel(kernel_name):
        return compile_nvbuild_kernel_host(
            kernel_name=kernel_name,
            arch=arch,
            toolchain_name=toolchain_name,
            toolchain_version=toolchain_version,
            config=config,
            build_target=build_target,
            threads=threads,
            clean=clean,
            incremental=incremental,
            localversion=localversion,
            dtb_name=dtb_name,
            build_modules=build_modules or build_dtb,
            dry_run=dry_run,
        )
    # Compiles the kernel directly on the host system.
    kernels_dir = os.path.join("storage", "kernels")
    kernel_dir = os.path.join(kernels_dir, kernel_name, "kernel", "kernel")
    cc_suffix = _host_cross_compile_suffix(toolchain_name, toolchain_version)

    # Base command for invoking make
    base_command = f"make -C {kernel_dir} ARCH={arch} -j{threads if threads else '$(nproc)'}{cc_suffix}"

    if localversion:
        base_command += f" LOCALVERSION=-{localversion}"

    # If use_current_config is specified, get the current kernel config and place it in the kernel directory
    if use_current_config:
        current_config_path = os.path.join(kernel_dir, ".config")
        zcat_command = f"zcat /proc/config.gz > {current_config_path}"
        print(f"Fetching current kernel config: {zcat_command}")
        if not dry_run:
            subprocess.run(zcat_command, shell=True, check=True)

    # Combine mrproper (if enabled), configuration, and kernel compilation into a single command
    combined_command = ""
    if clean and not incremental:
        combined_command += f"{base_command} mrproper && "
    if config or use_current_config:
        combined_command += f"{base_command} {config or 'oldconfig'} && "

    if build_dtb:
        top_level_makefile = os.path.join(kernels_dir, kernel_name, "Makefile")
        if os.path.exists(top_level_makefile):
            make_dir = os.path.join(kernels_dir, kernel_name)

            dtbs_make_command = f"make -C {make_dir} ARCH={arch} -j{threads if threads else '$(nproc)'}{cc_suffix}"

            dtbs_command = f"{dtbs_make_command} dtbs KERNEL_HEADERS={kernel_dir}"
            combined_command += f"{dtbs_command} && "
        else:
             combined_command += f"{base_command} dtbs && "

    if build_modules:
        top_level_makefile = os.path.join(kernels_dir, kernel_name, "Makefile")
        if os.path.exists(top_level_makefile):
            make_dir = os.path.join(kernels_dir, kernel_name)

            modules_make_command = f"make -C {make_dir} ARCH={arch} -j{threads if threads else '$(nproc)'}{cc_suffix}"

            modules_command = f"{modules_make_command} modules KERNEL_HEADERS={kernel_dir}"
            combined_command += f"{modules_command} && "
        else:
             combined_command += f"{base_command} modules && "

    if build_target:
        targets = build_target.split(',')
        for target in targets:
            if target == "kernel":
                combined_command += f"{base_command} && "
                combined_command += f"{base_command} modules_install INSTALL_MOD_PATH=../modules && "
                combined_command += f"mkdir -p ../modules/boot && "
                combined_command += f"cp {kernel_dir}/arch/{arch}/boot/Image ../modules/boot/Image.{localversion} && "
                # Copy the DTB file with modified filename to include localversion
                if dtb_name:
                    dtb_path = locate_dtb_file(kernel_name, dtb_name)
                    if dtb_path:
                        if overlays:
                            overlay_files = overlays.split(',')
                            overlay_paths = []
                            kernel_source_dir = os.path.join("storage", "kernels", kernel_name)
                            for overlay_file in overlay_files:
                                find_command = f"find {kernel_source_dir} -name {overlay_file}"
                                try:
                                    find_output = subprocess.check_output(find_command, shell=True, universal_newlines=True).strip()
                                    if find_output:
                                        overlay_paths.append(find_output.splitlines()[0])
                                    else:
                                        print(f"Error: Overlay file {overlay_file} not found.")
                                        return 1
                                except subprocess.CalledProcessError:
                                    print(f"Error: Failed to find overlay file {overlay_file}.")
                                    return 1

                            output_dtb_name = f"{os.path.splitext(dtb_name)[0]}-merged.dtb"
                            output_dtb_path = os.path.join(os.path.dirname(dtb_path), output_dtb_name)

                            fdtoverlay_command = f"fdtoverlay -i {dtb_path} -o {output_dtb_path} {' '.join(overlay_paths)}"
                            print(f"Running fdtoverlay command: {fdtoverlay_command}")
                            if not dry_run:
                                try:
                                    subprocess.run(fdtoverlay_command, shell=True, check=True)
                                except FileNotFoundError:
                                    print("Error: fdtoverlay command not found. Please install it.")
                                    return 1
                                except subprocess.CalledProcessError as e:
                                    print(f"Error running fdtoverlay: {e}")
                                    return 1

                            print(f"Renaming {output_dtb_path} to {dtb_path}")
                            if not dry_run:
                                os.rename(output_dtb_path, dtb_path)

                        new_dtb_name = f"{os.path.splitext(dtb_name)[0]}{localversion}.dtb"
                        combined_command += f"cp {dtb_path} ../modules/boot/{new_dtb_name} && "
                    else:
                        print(f"Warning: DTB file {dtb_name} not found in the kernel directory.")
            elif target == "modules":
                combined_command += f"{base_command} modules && "
                combined_command += f"{base_command} modules_install INSTALL_MOD_PATH=../modules && "
            elif target == "headers_install":
                headers_path = f"../headers"
                combined_command += f"mkdir -p {headers_path} && "
                combined_command += f"{base_command} headers_install INSTALL_HDR_PATH={headers_path} && "
            else:
                # General case for any target, including menuconfig
                combined_command += f"{base_command} {target} && "
    else:
        # If no specific target is provided, build the kernel and copy the Image
        combined_command += f"{base_command} && "
        combined_command += f"{base_command} modules_install INSTALL_MOD_PATH=../modules && "
        combined_command += f"mkdir -p ../modules/boot && "
         # Conditional logic for the kernel image filename
        image_filename = f"Image.{localversion}" if localversion else "Image"
        combined_command += f"cp {kernel_dir}/arch/{arch}/boot/Image ../modules/boot/{image_filename} && "

        # Copy the DTB file with modified filename to include localversion
        if dtb_name:
            dtb_path = locate_dtb_file(kernel_name, dtb_name)
            if dtb_path:
                new_dtb_name = f"{os.path.splitext(dtb_name)[0]}{localversion}.dtb"
                combined_command += f"cp {dtb_path} ../modules/boot/{new_dtb_name}"

    # Remove any trailing '&&'
    combined_command = combined_command.rstrip(' &&')

    # Adjust permissions before running ctags to avoid permission issues
    if generate_ctags:
        combined_command += f" && chmod -R u+w {kernel_dir} && ctags -R -f ../tags {kernel_dir}"

    # Run the combined command directly on the host
    if dry_run:
        print(f"[Dry-run] Would run combined command: {combined_command}")
        return 0
    print(f"Running combined command: {combined_command}")
    proc = subprocess.run(combined_command, shell=True)
    return proc.returncode


def compile_kernel_docker(kernel_name, arch, toolchain_name=None, toolchain_version=None, rpi_model=None, config=None, generate_ctags=False, build_target=None, threads=None, clean=True, incremental=True, use_current_config=False, localversion="", dtb_name=None, build_dtb=False, build_modules=False, overlays=None, dry_run=False):
    if is_nvbuild_kernel(kernel_name):
        ensure_docker_image(jp7=True, dry_run=dry_run)
        return compile_nvbuild_kernel_docker(
            kernel_name=kernel_name,
            arch=arch,
            toolchain_name=toolchain_name,
            toolchain_version=toolchain_version,
            config=config,
            build_target=build_target,
            threads=threads,
            clean=clean,
            incremental=incremental,
            localversion=localversion,
            dtb_name=dtb_name,
            build_modules=build_modules or build_dtb,
            dry_run=dry_run,
        )
    ensure_docker_image(jp7=False, dry_run=dry_run)
    # Compiles the kernel using Docker for encapsulation.
    kernels_dir = os.path.join("storage", "kernels")
    toolchains_dir = os.path.join("storage", "toolchains")

    # Create Docker volume arguments to mount kernel, toolchain, and overlays directories into a builder working directory
    kernels_dir_abs = os.path.abspath(kernels_dir)
    toolchains_dir_abs = os.path.abspath(toolchains_dir)
    volume_args = ["-v", f"{kernels_dir_abs}:/builder/kernels", "-v", f"{toolchains_dir_abs}:/builder/toolchains"]

    # Get current user ID and group ID to run Docker commands as the current user
    user_id = os.getuid()
    group_id = os.getgid()

    # Get total number of CPUs on the machine
    total_cpus = os.cpu_count()

    # -t requires a real TTY; kb-menu (and CI) pipe stdout to tee, which breaks
    # "docker run -it" with "the input device is not a TTY". Batch builds do
    # not need a pseudo-TTY.
    docker_tty = ["-it"] if (sys.stdin.isatty() and sys.stdout.isatty()) else []

    # Construct the Docker command
    docker_command_base = [
        "docker", "run", "--rm", *docker_tty, "--init", "-u", f"{user_id}:{group_id}",
        "--cpus=" + str(total_cpus)
    ] + volume_args + [
        "-w", "/builder", "kernel_builder", "/bin/bash", "-c"
    ]

    # Base command for invoking make
    base_command = f"make -C /builder/kernels/{kernel_name}/kernel/kernel ARCH={arch} -j{threads if threads else '$(nproc)'}"

    if toolchain_name and toolchain_version:
        base_command += f" CROSS_COMPILE=/builder/toolchains/{toolchain_name}/{toolchain_version}/bin/{toolchain_name}-"

    if localversion:
        base_command += f" LOCALVERSION=-{localversion}"

    env = os.environ.copy()
    if toolchain_name and toolchain_version:
        env["PATH"] = f"/builder/toolchains/{toolchain_name}/{toolchain_version}/bin:" + env["PATH"]

    # If use_current_config is specified, get the current kernel config and place it in the kernel directory
    if use_current_config:
        current_config_path = f"/builder/kernels/{kernel_name}/kernel/kernel/.config"
        zcat_command = f"zcat /proc/config.gz > {current_config_path}"
        print(f"Fetching current kernel config: {zcat_command}")
        if not dry_run:
            subprocess.run(zcat_command, shell=True, check=True)

    # Combine mrproper (if enabled), configuration, and kernel compilation into a single Docker run command
    combined_command_phase_1 = ""
    if clean and not incremental:
        combined_command_phase_1 += f"{base_command} mrproper && "
    if config or use_current_config:
        combined_command_phase_1 += f"{base_command} {config or 'oldconfig'} && "

    if build_dtb:
        top_level_makefile_path_host = os.path.join("storage", "kernels", kernel_name, "Makefile")
        if os.path.exists(top_level_makefile_path_host):
            make_dir_docker = f"/builder/kernels/{kernel_name}"
            kernel_source_dir_docker = f"/builder/kernels/{kernel_name}/kernel/kernel"

            dtbs_make_command = f"make -C {make_dir_docker} ARCH={arch} -j{threads if threads else '$(nproc)'}"
            if toolchain_name and toolchain_version:
                dtbs_make_command += f" CROSS_COMPILE=/builder/toolchains/{toolchain_name}/{toolchain_version}/bin/{toolchain_name}-"

            dtbs_command = f"{dtbs_make_command} dtbs KERNEL_HEADERS={kernel_source_dir_docker}"
            combined_command_phase_1 += f"{dtbs_command} && "
        else:
            combined_command_phase_1 += f"{base_command} dtbs && "

    if build_modules:
        top_level_makefile_path_host = os.path.join("storage", "kernels", kernel_name, "Makefile")
        if os.path.exists(top_level_makefile_path_host):
            make_dir_docker = f"/builder/kernels/{kernel_name}"
            kernel_source_dir_docker = f"/builder/kernels/{kernel_name}/kernel/kernel"

            modules_make_command = f"make -C {make_dir_docker} ARCH={arch} -j{threads if threads else '$(nproc)'}"
            if toolchain_name and toolchain_version:
                modules_make_command += f" CROSS_COMPILE=/builder/toolchains/{toolchain_name}/{toolchain_version}/bin/{toolchain_name}-"

            modules_command = f"{modules_make_command} modules KERNEL_HEADERS={kernel_source_dir_docker}"
            combined_command_phase_1 += f"{modules_command} && "
        else:
            combined_command_phase_1 += f"{base_command} modules && "

    # Add the kernel and module build targets to the first Docker invocation
    if build_target:
        targets = build_target.split(',')
        for target in targets:
            if target == "kernel":
                combined_command_phase_1 += f"{base_command} && "
                combined_command_phase_1 += f"{base_command} modules_install INSTALL_MOD_PATH=/builder/kernels/{kernel_name}/modules && "
            elif target == "modules":
                combined_command_phase_1 += f"{base_command} modules && "
                combined_command_phase_1 += f"{base_command} modules_install INSTALL_MOD_PATH=/builder/kernels/{kernel_name}/modules && "
            elif target == "headers_install":
                headers_path = f"/builder/kernels/{kernel_name}/headers"
                combined_command_phase_1 += f"mkdir -p {headers_path} && "
                combined_command_phase_1 += f"{base_command} headers_install INSTALL_HDR_PATH={headers_path} && "
            else:
                # General case for any target, including menuconfig
                combined_command_phase_1 += f"{base_command} {target} && "
    else:
        # If no specific target is provided, build the kernel and modules
        combined_command_phase_1 += f"{base_command} && "
        combined_command_phase_1 += f"{base_command} modules_install INSTALL_MOD_PATH=/builder/kernels/{kernel_name}/modules && "

    # Remove any trailing '&&'
    combined_command_phase_1 = combined_command_phase_1.rstrip(' &&')

    # Adjust permissions before running ctags to avoid permission issues
    if generate_ctags:
        combined_command_phase_1 += f" && chmod -R u+w /builder/kernels/{kernel_name}/kernel && ctags -R -f /builder/tags /builder/kernels/{kernel_name}/kernel"

    # Run the first Docker container session for kernel build and module installation
    if dry_run:
        print(f"[Dry-run] Would run combined command (Phase 1): {' '.join(docker_command_base + [combined_command_phase_1])}")
    else:
        full_command_phase_1 = docker_command_base + [combined_command_phase_1]
        print(f"Running Docker command (Phase 1): {' '.join(full_command_phase_1)}")
        phase1_rc = subprocess.Popen(full_command_phase_1, env=env).wait()
        if phase1_rc != 0:
            return phase1_rc

    # Phase 1.5: Handle Overlays
    if overlays:
        if not dtb_name:
            print("Error: --dtb-name must be provided when using --overlays.")
            return 1

        # Find the base DTB file path inside the container
        base_dtb_path_host = locate_dtb_file(kernel_name, dtb_name)
        if not base_dtb_path_host:
            print(f"Error: Base DTB file {dtb_name} not found.")
            return 1

        base_dtb_path_docker = _host_kernel_path_to_docker(base_dtb_path_host, kernels_dir_abs)

        # Find the overlay files paths inside the container
        overlay_files = overlays.split(',')
        overlay_paths_docker = []
        kernel_source_dir_host = os.path.join("storage", "kernels", kernel_name)
        for overlay_file in overlay_files:
            find_command = f"find {kernel_source_dir_host} -name {overlay_file}"
            try:
                find_output = subprocess.check_output(find_command, shell=True, universal_newlines=True).strip()
                if find_output:
                    overlay_path_host = find_output.splitlines()[0]
                    overlay_path_docker = _host_kernel_path_to_docker(overlay_path_host, kernels_dir_abs)
                    overlay_paths_docker.append(overlay_path_docker)
                else:
                    print(f"Error: Overlay file {overlay_file} not found.")
                    return 1
            except subprocess.CalledProcessError:
                print(f"Error: Failed to find overlay file {overlay_file}.")
                return 1

        # Construct the fdtoverlay command for docker
        output_dtb_name = f"{os.path.splitext(dtb_name)[0]}-merged.dtb"
        output_dtb_path_docker = os.path.join(os.path.dirname(base_dtb_path_docker), output_dtb_name)

        fdtoverlay_command = f"fdtoverlay -i {base_dtb_path_docker} -o {output_dtb_path_docker} {' '.join(overlay_paths_docker)}"

        if dry_run:
            print(f"[Dry-run] Would run fdtoverlay command in docker: {fdtoverlay_command}")
        else:
            print(f"Running fdtoverlay command in docker: {fdtoverlay_command}")
            process = subprocess.Popen(docker_command_base + [fdtoverlay_command])
            process.wait()
            if process.returncode != 0:
                print("Error: fdtoverlay command failed.")
                return 1

        # Now, on the host, rename the file
        output_dtb_path_host = os.path.join(os.path.dirname(base_dtb_path_host), output_dtb_name)
        print(f"Renaming {output_dtb_path_host} to {base_dtb_path_host}")
        if not dry_run:
            os.rename(output_dtb_path_host, base_dtb_path_host)

    # Phase 2: Copy Image and DTB after kernel build
    commands_phase_2 = []
    # Conditional logic for the kernel image filename
    image_filename = f"Image.{localversion}" if localversion else "Image"
    commands_phase_2.append(f"mkdir -p /builder/kernels/{kernel_name}/modules/boot")
    commands_phase_2.append(f"cp /builder/kernels/{kernel_name}/kernel/kernel/arch/{arch}/boot/Image /builder/kernels/{kernel_name}/modules/boot/{image_filename}")

    # Copy the DTB file with modified filename to include localversion
    if dtb_name:
        dtb_path = locate_dtb_file(kernel_name, dtb_name)
        if dtb_path:
            dtb_path_docker = _host_kernel_path_to_docker(dtb_path, kernels_dir_abs)
            new_dtb_name = f"{os.path.splitext(dtb_name)[0]}{localversion}.dtb"
            commands_phase_2.append(f"cp {dtb_path_docker} /builder/kernels/{kernel_name}/modules/boot/{new_dtb_name}")
        else:
            print(f"Warning: DTB file {dtb_name} not found in the kernel directory.")

    combined_command_phase_2 = " && ".join(commands_phase_2)

    # Run the second Docker container session to copy the kernel Image and DTB
    if dry_run:
        print(f"[Dry-run] Would run combined command (Phase 2): {' '.join(docker_command_base + [combined_command_phase_2])}")
    else:
        full_command_phase_2 = docker_command_base + [combined_command_phase_2]
        print(f"Running Docker command (Phase 2): {' '.join(full_command_phase_2)}")
        process = subprocess.Popen(full_command_phase_2, env=env)
        process.wait()
        if process.returncode != 0:
            print("Error: Docker encountered an error during execution.")
            return process.returncode

    return 0


def main():
    parser = argparse.ArgumentParser(description="Kernel Builder Script")
    subparsers = parser.add_subparsers(dest="command")

    # Build Docker image command
    build_parser = subparsers.add_parser("build")
    build_parser.add_argument("--rebuild", action="store_true", help="Rebuild the Docker image without using the cache")
    build_parser.add_argument("--jp7", action="store_true", help="Build the JetPack 7.x nvbuild Docker image (kernel_builder_jp7)")

    # Clone kernel command
    clone_parser = subparsers.add_parser("clone-kernel")
    clone_parser.add_argument("--kernel-source-url", required=True, help="URL of the kernel source to be cloned")
    clone_parser.add_argument("--kernel-name", required=True, help="Name for the kernel subfolder")
    clone_parser.add_argument("--git-tag", help="Git tag to check out after cloning the kernel source")

    # Clone toolchain command
    clone_toolchain_parser = subparsers.add_parser("clone-toolchain")
    clone_toolchain_parser.add_argument("--toolchain-url", required=True, help="URL of the toolchain to be cloned")
    clone_toolchain_parser.add_argument("--toolchain-name", required=True, help="Name for the toolchain subfolder")
    clone_toolchain_parser.add_argument("--toolchain-version", required=True, help="Version for the toolchain")
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
    compile_parser.add_argument("--toolchain-version", help="Version of the toolchain to use")
    compile_parser.add_argument("--rpi-model", help="Specify the Raspberry Pi model to compile the kernel for (e.g., rpi3 or rpi4)")
    compile_parser.add_argument("--config", help="Kernel configuration to use for compilation (e.g., defconfig, tegra_defconfig)")
    compile_parser.add_argument("--generate-ctags", action="store_true", help="Generate ctags/tags file for the kernel source")
    compile_parser.add_argument("--build-target", help="Comma-separated list of build targets (e.g., kernel,dtbs,modules,bindeb-pkg). If 'kernel' is specified, it will directly call make without a target.")
    compile_parser.add_argument("--threads", type=int, help="Number of threads to use for compilation (default: use all available cores)")
    compile_parser.add_argument("--clean", action="store_true", help="Delete kernel_out / run mrproper before building (full rebuild)")
    compile_parser.add_argument(
        "--no-incremental",
        dest="incremental",
        action="store_false",
        help="Force full nvbuild (rsync --delete + defconfig) even when kernel_out exists",
    )
    compile_parser.set_defaults(incremental=True)
    compile_parser.add_argument("--use-current-config", action="store_true", help="Use the current system kernel configuration for building the kernel")
    compile_parser.add_argument("--localversion", help="Set a local version string to append to the kernel version")
    compile_parser.add_argument("--host-build", action="store_true", help="Compile the kernel directly on the host instead of using Docker")
    compile_parser.add_argument("--dtb-name", help="Name of the DTB file to be copied alongside the compiled kernel")
    compile_parser.add_argument("--build-dtb", action="store_true", help="Build the Device Tree Blob (DTB) separately using 'make dtbs'.")
    compile_parser.add_argument("--build-modules", action="store_true", help="Build kernel modules separately.")
    compile_parser.add_argument("--overlays", help="Comma-separated list of DTBO files to apply as overlays.")
    compile_parser.add_argument("--dry-run", action="store_true", help="Print the commands without executing them")

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
        build_docker_image(rebuild=args.rebuild, jp7=args.jp7)
    elif args.command == "clone-kernel":
        clone_kernel(kernel_source_url=args.kernel_source_url, kernel_name=args.kernel_name, git_tag=args.git_tag)
    elif args.command == "clone-toolchain":
        clone_toolchain(toolchain_url=args.toolchain_url, toolchain_name=args.toolchain_name, toolchain_version=args.toolchain_version, git_tag=args.git_tag)
    elif args.command == "clone-overlays":
        clone_overlays(overlays_url=args.overlays_url, kernel_name=args.kernel_name, git_tag=args.git_tag)
    elif args.command == "clone-device-tree":
        clone_device_tree(device_tree_url=args.device_tree_url, kernel_name=args.kernel_name, git_tag=args.git_tag)
    elif args.command == "compile":
        if is_nvbuild_kernel(args.kernel_name):
            default_name, default_version = jp7_toolchain_defaults()
            if not args.toolchain_name:
                args.toolchain_name = default_name
            if not args.toolchain_version:
                args.toolchain_version = default_version
            if not args.dry_run:
                ensure_jp7_toolchain_storage(_repo_root())
        elif (
            args.toolchain_name
            and args.toolchain_version
            and not args.dry_run
        ):
            gcc_rel = os.path.join(
                "storage",
                "toolchains",
                args.toolchain_name,
                args.toolchain_version,
                "bin",
                f"{args.toolchain_name}-gcc",
            )
            if not os.path.isfile(os.path.abspath(gcc_rel)):
                abs_gcc = os.path.abspath(gcc_rel)
                print(
                    f"Error: Cross-compiler not found: {abs_gcc}",
                    file=sys.stderr,
                )
                print(
                    "Expected layout: storage/toolchains/<toolchain-name>/<toolchain-version>/bin/<toolchain-name>-gcc",
                    file=sys.stderr,
                )
                print(
                    "Clone the toolchain from the repository root, for example:\n"
                    "  python3 python/kernel_builder.py clone-toolchain \\\n"
                    "    --toolchain-url https://github.com/alxhoff/Jetson-Linux-Toolchain \\\n"
                    "    --toolchain-name aarch64-buildroot-linux-gnu \\\n"
                    "    --toolchain-version 9.3",
                    file=sys.stderr,
                )
                print(
                    "If you use a different prefix, set --toolchain-name / --toolchain-version to match the bin/ filenames.",
                    file=sys.stderr,
                )
                sys.exit(1)
        if args.host_build:
            rc = compile_kernel_host(
                kernel_name=args.kernel_name,
                arch=args.arch,
                toolchain_name=args.toolchain_name,
                toolchain_version=args.toolchain_version,
                config=args.config,
                generate_ctags=args.generate_ctags,
                build_target=args.build_target,
                threads=args.threads,
                clean=args.clean,
                incremental=args.incremental,
                use_current_config=args.use_current_config,
                localversion=args.localversion or "",
                dtb_name=args.dtb_name,
                build_dtb=args.build_dtb,
                build_modules=args.build_modules,
                overlays=args.overlays,
                dry_run=args.dry_run,
            )
        else:
            rc = compile_kernel_docker(
                kernel_name=args.kernel_name,
                arch=args.arch,
                toolchain_name=args.toolchain_name,
                toolchain_version=args.toolchain_version,
                rpi_model=args.rpi_model,
                config=args.config,
                generate_ctags=args.generate_ctags,
                build_target=args.build_target,
                threads=args.threads,
                clean=args.clean,
                incremental=args.incremental,
                use_current_config=args.use_current_config,
                localversion=args.localversion or "",
                dtb_name=args.dtb_name,
                build_dtb=args.build_dtb,
                build_modules=args.build_modules,
                overlays=args.overlays,
                dry_run=args.dry_run,
            )
        sys.exit(rc)
    elif args.command == "inspect":
        inspect_docker_image()
    elif args.command == "cleanup":
        cleanup_docker()

if __name__ == "__main__":
    main()

