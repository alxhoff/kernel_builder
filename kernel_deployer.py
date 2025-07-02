#!/usr/bin/env python3

import argparse
import os
import subprocess
from pathlib import Path

def create_deb_package(kernel_name, localversion=None, dtb_name="tegra234-p3701-0000-p3737-0000.dtb"):
    import shutil
    import tempfile

    # Define kernel version and paths
    modules_base_dir = os.path.join("kernels", kernel_name, "modules")
    kernel_versions = os.listdir(os.path.join(modules_base_dir, "lib", "modules"))
    kernel_version = next((version for version in kernel_versions if version.endswith(localversion)), kernel_versions[-1]) if localversion else kernel_versions[0]

    kernel_image = os.path.join(modules_base_dir, "boot", f"Image.{localversion}") if localversion else os.path.join(modules_base_dir, "boot", "Image")

    dtb_base = dtb_name[:-4] if dtb_name.endswith(".dtb") else dtb_name
    print(f"DTB base: {dtb_base}")

    #  if localversion:
    #      dtb_filename = f"{dtb_base}-{localversion}.dtb"
    #  else:
    #      dtb_filename = f"{dtb_base}.dtb"

    dtb_filename = (
        f"{dtb_base}{localversion}.dtb"
        if localversion
        else f"{dtb_name}"
    )
    print(f"DTB filename: {dtb_filename}")
    dtb_file = os.path.join(modules_base_dir, "boot", dtb_filename)
    print(f"DTB file: {dtb_file}")

    modules_dir = os.path.join(modules_base_dir, "lib", "modules", kernel_version)

    # Ensure required files exist
    if not os.path.exists(kernel_image):
        print("Error: Required kernel files are missing.")
        return None
    elif not os.path.exists(dtb_file):
        print("Error: Required dtb files are missing.")
        return None
    elif not os.path.exists(modules_dir):
        print("Error: Required modules dir missing.")
        return None

    # Define a persistent output directory for the .deb package
    output_dir = os.path.abspath("kernel_debs")  # Save in 'kernel_debs' folder
    os.makedirs(output_dir, exist_ok=True)  # Ensure directory exists

    # Define the final .deb package filename
    package_name = f"linux-custom-{kernel_version}.deb"
    deb_file_path = os.path.join(output_dir, package_name)

    with tempfile.TemporaryDirectory() as temp_dir:
        debian_dir = os.path.join(temp_dir, package_name.replace(".deb", ""))
        os.makedirs(debian_dir, exist_ok=True)

        # Create DEBIAN control directory
        debian_control_dir = os.path.join(debian_dir, "DEBIAN")
        os.makedirs(debian_control_dir, exist_ok=True)

        control_content = f"""Package: {package_name.replace('.deb', '')}
Version: {kernel_version}
Architecture: arm64
Maintainer: Your Name <your@email.com>
Description: Custom Jetson Kernel {kernel_version}
Depends: initramfs-tools
Section: kernel
Priority: optional
"""
        with open(os.path.join(debian_control_dir, "control"), "w") as control_file:
            control_file.write(control_content)

        # Set up post-installation script
        postinst_content = f"""#!/bin/bash
set -e
echo "Installing custom kernel {kernel_version}"
cp /boot/Image /boot/Image.previous || true
mv /boot/Image.{localversion} /boot/Image
depmod {kernel_version}
update-initramfs -c -k {kernel_version}

# Update extlinux.conf
sed -i 's|LINUX .*|LINUX /boot/Image|' /boot/extlinux/extlinux.conf
sed -i 's|INITRD .*|INITRD /boot/initrd.img-{kernel_version}|' /boot/extlinux/extlinux.conf
sed -i 's|FDT .*|FDT /boot/dtb/{dtb_filename}|' /boot/extlinux/extlinux.conf
"""
        with open(os.path.join(debian_control_dir, "postinst"), "w") as postinst_file:
            postinst_file.write(postinst_content)

        # Make postinst script executable
        os.chmod(os.path.join(debian_control_dir, "postinst"), 0o755)

        # Copy necessary files into package structure
        boot_dir = os.path.join(debian_dir, "boot")
        dtb_dir = os.path.join(debian_dir, "boot/dtb")
        lib_modules_dir = os.path.join(debian_dir, "lib/modules")

        os.makedirs(boot_dir, exist_ok=True)
        os.makedirs(dtb_dir, exist_ok=True)
        os.makedirs(lib_modules_dir, exist_ok=True)

        shutil.copy(kernel_image, boot_dir)
        shutil.copy(dtb_file, dtb_dir)

        def ignore_symlinks(src, names):
            ignored = []
            for name in names:
                full_path = os.path.join(src, name)
                if os.path.islink(full_path):
                    target = os.readlink(full_path)
                    if not os.path.exists(target):  # Ignore broken symlinks
                        print(f"⚠️  Skipping broken symlink: {full_path} -> {target}")
                        ignored.append(name)
            return ignored

        shutil.copytree(
            modules_dir,
            os.path.join(lib_modules_dir, kernel_version),
            symlinks=True,  # Preserve symlinks
            ignore=ignore_symlinks  # Ignore broken symlinks
        )


        # Build the Debian package
        subprocess.run(["dpkg-deb", "--build", debian_dir, deb_file_path], check=True)

        # Print the full path of the generated .deb package
        print("")
        print("✅ Debian package successfully created!")
        print(f"📂 Saved to: {deb_file_path}")
        print("")

        return deb_file_path

def deploy_x86(dry_run=False, localversion=None):
    # Deploys the compiled kernel to an x86 host machine.
    modules_base_dir = os.path.join("kernels", "compiled", "modules")
    kernel_versions = os.listdir(os.path.join(modules_base_dir, "lib", "modules"))

    # Determine the kernel version to use, either from argument or default to the first
    kernel_version = next((version for version in kernel_versions if localversion in version), kernel_versions[0]) if localversion else kernel_versions[0]
    modules_dir = os.path.join(modules_base_dir, "lib", "modules", kernel_version)
    kernel_image = os.path.join("kernels", "compiled", f"vmlinuz-{kernel_version}")

    if not os.path.exists(kernel_image):
        print(f"Error: Kernel image {kernel_image} does not exist.")
        return
    if not os.path.exists(modules_dir):
        print(f"Error: Modules directory {modules_dir} does not exist.")
        return

    # Copy the kernel image to /boot
    boot_dir = "/boot"
    print(f"Copying {kernel_image} to {boot_dir}")
    if not dry_run:
        subprocess.run(["sudo", "cp", kernel_image, boot_dir], check=True)

    # Copy the modules to /lib/modules
    target_modules_dir = "/lib/modules"
    print(f"Copying modules from {modules_dir} to {target_modules_dir}")
    if not dry_run:
        subprocess.run(["sudo", "cp", "-r", modules_dir, target_modules_dir], check=True)

def deploy_device(device_ip, user, dry_run=False, localversion=None, kernel_only=False):
    modules_base_dir = os.path.join("kernels", "compiled", "modules")
    kernel_versions = os.listdir(os.path.join(modules_base_dir, "lib", "modules"))

    kernel_version = next((version for version in kernel_versions if localversion in version), kernel_versions[0]) if localversion else kernel_versions[0]
    modules_dir = os.path.join(modules_base_dir, "lib", "modules", kernel_version)
    kernel_image = os.path.join("kernels", "compiled", f"vmlinuz-{kernel_version}")

    if not os.path.exists(kernel_image):
        print(f"Error: Kernel image {kernel_image} does not exist.")
        return
    if not os.path.exists(modules_dir):
        print(f"Error: Modules directory {modules_dir} does not exist.")
        return

    remote_boot_dir = f"{user}@{device_ip}:/boot"
    print(f"Copying {kernel_image} to {remote_boot_dir}")
    if not dry_run:
        subprocess.run(["scp", kernel_image, remote_boot_dir], check=True)

    if not kernel_only:
        remote_modules_dir = f"{user}@{device_ip}:/lib/modules/{kernel_version}"
        print(f"Copying modules from {modules_dir} to {remote_modules_dir}")
        if not dry_run:
            subprocess.run(["scp", "-r", modules_dir, remote_modules_dir], check=True)

def deploy_jetson(kernel_name, device_ip, user, dry_run=False, localversion=None, dtb=False, kernel_only=False):
    # Deploys the compiled kernel to a remote Jetson device via SCP.
    modules_base_dir = os.path.join("kernels", kernel_name, "modules")
    kernel_versions = os.listdir(os.path.join(modules_base_dir, "lib", "modules"))
    kernel_version = next((version for version in kernel_versions if version.endswith(localversion)), kernel_versions[-1]) if localversion else kernel_versions[0]

    # Define paths for deployment
    kernel_image = os.path.join(modules_base_dir, "boot", f"Image.{localversion}") if localversion else os.path.join(modules_base_dir, "boot", "Image")
    dtb_file = os.path.join(modules_base_dir, "boot", f"tegra234-p3701-0000-p3737-0000{localversion}.dtb") if localversion else os.path.join(modules_base_dir, "boot", "tegra234-p3701-0000-p3737-0000.dtb")
    modules_dir = os.path.join(modules_base_dir, "lib", "modules", kernel_version)

    # Ensure required files exist
    if not os.path.exists(kernel_image):
        print(f"Error: Kernel image {kernel_image} does not exist.")
        return
    if not os.path.exists(dtb_file):
        print(f"Error: Device Tree Blob {dtb_file} does not exist.")
        return
    if not os.path.exists(modules_dir):
        print(f"Error: Modules directory {modules_dir} does not exist.")
        return

    if not kernel_only:
        # Compress the modules directory before sending to the remote device
        modules_archive = f"/tmp/{kernel_version}.tar.gz"
        print(f"Compressing {modules_dir} into {modules_archive}")
        if not dry_run:
            subprocess.run(["tar", "-czf", modules_archive, "-C", os.path.dirname(modules_dir), os.path.basename(modules_dir)], check=True)

        # Copy the compressed modules archive to /tmp on the Jetson device
        print(f"Copying {modules_archive} to /tmp on remote device")
        if not dry_run:
            subprocess.run(["scp", modules_archive, f"{user}@{device_ip}:/tmp/"], check=True)

        # Extract the modules archive on the remote device
        extract_command = f"ssh root@{device_ip} 'mkdir -p /tmp/modules && tar -xzf /tmp/{kernel_version}.tar.gz -C /tmp/modules'"
        print(f"Extracting modules on remote device: {extract_command}")
        if not dry_run:
            subprocess.run(extract_command, shell=True, check=True)

    # Copy kernel image to /tmp
    print(f"Copying {kernel_image} to /tmp on remote device")
    if not dry_run:
        subprocess.run(["scp", kernel_image, f"{user}@{device_ip}:/tmp/"], check=True)

    # Copy Device Tree Blob to /tmp
    print(f"Copying {dtb_file} to /tmp on remote device")
    if not dry_run:
        subprocess.run(["scp", dtb_file, f"{user}@{device_ip}:/tmp/"], check=True)

    # Rename the current kernel image to Image.previous
    rename_command = f"ssh root@{device_ip} 'if [ -f /boot/Image ]; then mv /boot/Image /boot/Image.previous; fi'"
    print(f"Renaming existing kernel image to Image.previous: {rename_command}")
    if not dry_run:
        subprocess.run(rename_command, shell=True, check=True)

    # Move kernel image to /boot as root
    move_command = f"ssh root@{device_ip} 'mv /tmp/{os.path.basename(kernel_image)} /boot/'"
    print(f"Moving kernel image to /boot on remote device: {move_command}")
    if not dry_run:
        subprocess.run(move_command, shell=True, check=True)

    # Move DTB file to /boot/dtb as root
    move_command = f"ssh root@{device_ip} 'mv /tmp/{os.path.basename(dtb_file)} /boot/dtb/{os.path.basename(dtb_file)}'"
    print(f"Moving DTB file to /boot/dtb on remote device: {move_command}")
    if not dry_run:
        subprocess.run(move_command, shell=True, check=True)

    if not kernel_only:
        # Rename existing kernel modules folder to _previous, if it exists
        rename_modules_command = f"ssh root@{device_ip} 'if [ -d /lib/modules/{kernel_version} ]; then rm -rf /lib/modules/{kernel_version}_previous && mv /lib/modules/{kernel_version} /lib/modules/{kernel_version}_previous; fi'"
        print(f"Renaming existing kernel modules to {kernel_version}_previous on remote device: {rename_modules_command}")
        if not dry_run:
            subprocess.run(rename_modules_command, shell=True, check=True)

        # Move modules to the final destination as root
        move_command = f"ssh root@{device_ip} 'cp -r /tmp/modules/{kernel_version} /lib/modules/'"
        print(f"Moving kernel modules to /lib/modules/{kernel_version} on remote device: {move_command}")
        if not dry_run:
            subprocess.run(move_command, shell=True, check=True)

        # Run depmod on the target device
        depmod_command = f"ssh root@{device_ip} 'depmod {kernel_version}'"
        print(f"Running depmod on the target device: {depmod_command}")
        if not dry_run:
            subprocess.run(depmod_command, shell=True, check=True)

    # Backup extlinux.conf before updating
    extlinux_conf_path = "/boot/extlinux/extlinux.conf"
    backup_extlinux_conf_command = f"ssh root@{device_ip} 'cp {extlinux_conf_path} {extlinux_conf_path}.previous'"
    print(f"Backing up extlinux.conf to {extlinux_conf_path}.previous: {backup_extlinux_conf_command}")
    if not dry_run:
        subprocess.run(backup_extlinux_conf_command, shell=True, check=True)

    # Update extlinux.conf to use the new kernel
    new_kernel_entry = f"      LINUX /boot/Image.{localversion if localversion else ''}"
    update_command = (
        f"ssh root@{device_ip} \"sed -i.bak 's|^[[:space:]]*LINUX .*|{new_kernel_entry}|' {extlinux_conf_path}\""
    )
    print(f"Updating {extlinux_conf_path} on remote device to use new kernel: {new_kernel_entry}")
    print(f"Command: {update_command}")
    if not dry_run:
        subprocess.run(update_command, shell=True, check=True)

    # Run update-initramfs on the target device
    initramfs_command = f"ssh root@{device_ip} 'update-initramfs -c -k {kernel_version}'"
    print(f"Regenerating initramfs on remote device: {initramfs_command}")
    if not dry_run:
        subprocess.run(initramfs_command, shell=True, check=True)

    # Update extlinux.conf to use the new initrd (INITRD)
    new_initrd_entry = f"      INITRD /boot/initrd.img-{kernel_version}"
    update_initrd_command = (
        f"ssh root@{device_ip} \"sed -i.bak 's|^[[:space:]]*INITRD .*|{new_initrd_entry}|' {extlinux_conf_path}\""
    )
    print(f"Updating {extlinux_conf_path} on remote device to use new initrd: {new_initrd_entry}")
    if not dry_run:
        subprocess.run(update_initrd_command, shell=True, check=True)

    # Update extlinux.conf to use the new FDT (Flattened Device Tree)
    if dtb:
        new_fdt_entry = f"      FDT /boot/dtb/{os.path.basename(dtb_file)}"
        update_fdt_command = (
            f"ssh root@{device_ip} \"sed -i.bak 's|^[[:space:]]*FDT .*|{new_fdt_entry}|' {extlinux_conf_path}\""
        )
        print(f"Updating {extlinux_conf_path} on remote device to use new FDT: {new_fdt_entry}")
        if not dry_run:
            subprocess.run(update_fdt_command, shell=True, check=True)

def locate_compiled_modules(kernel_name, target_modules):
    """
    Locate the compiled kernel module (.ko) files for the given list of target modules.
    """
    kernels_dir = os.path.join("kernels", kernel_name)
    compiled_modules = []

    for module in target_modules:
        # Search from the root of the kernel directory
        find_command = f"find {kernels_dir} -type f -name {module}.ko"
        try:
            find_output = subprocess.check_output(find_command, shell=True, universal_newlines=True).strip()
            if find_output:
                found_paths = find_output.splitlines()
                compiled_modules.extend(found_paths)
            else:
                print(f"Warning: Module {module}.ko not found.")
        except subprocess.CalledProcessError:
            print(f"Warning: Could not locate compiled module for {module}. Make sure the module was built successfully.")

    # Remove duplicates in case there are multiple paths (e.g., redundant overlays)
    compiled_modules = list(set(compiled_modules))

    return compiled_modules

def deploy_targeted_modules(kernel_name, device_ip, user, dry_run=False):
    target_modules_file = os.path.join("target_modules.txt")
    if not os.path.exists(target_modules_file):
        raise FileNotFoundError("Error: target_modules.txt not found. Please create the file with the list of modules to build.")

    with open(target_modules_file, 'r') as file:
        target_modules = [line.strip() for line in file if line.strip()]

    if not target_modules:
        raise ValueError("Error: No target modules specified in target_modules.txt.")

    print(f"Modules to deploy: {target_modules}")

    # Determine the kernel version on the target device
    kernel_version = subprocess.check_output(f"ssh {user}@{device_ip} 'uname -r'", shell=True).strip().decode('utf-8')

    # Base path for modules on the host
    kernels_dir = os.path.join("kernels", kernel_name)

    # Process each module in the target_modules file
    for module_path in target_modules:
        # Full source path of the module on the host
        source_path = os.path.join(kernels_dir, module_path)
        if not os.path.exists(source_path):
            print(f"Warning: Module {source_path} not found. Skipping.")
            continue

        # Target directory on the remote device
        target_dir = f"/lib/modules/{kernel_version}/{os.path.dirname(module_path)}"
        remote_target_dir = f"{user}@{device_ip}:{target_dir}"
        print(f"Deploying {source_path} to {remote_target_dir}")

        # Ensure target directory exists on the remote device
        mkdir_command = f"ssh {user}@{device_ip} 'sudo mkdir -p {target_dir}'"
        if not dry_run:
            subprocess.run(mkdir_command, shell=True, check=True)

        # Copy the module to the remote device
        scp_command = ["scp", source_path, f"{remote_target_dir}/"]
        if not dry_run:
            subprocess.run(scp_command, check=True)

    # Run depmod to refresh module dependencies
    depmod_command = f"ssh {user}@{device_ip} 'sudo depmod -a {kernel_version}'"
    print(f"Running depmod on the target device: {depmod_command}")
    if not dry_run:
        subprocess.run(depmod_command, shell=True, check=True)

def main():
    parser = argparse.ArgumentParser(description="Kernel Deployer Script")
    subparsers = parser.add_subparsers(dest="command")

    # Deploy to x86 command
    deploy_x86_parser = subparsers.add_parser("deploy-x86")
    deploy_x86_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')
    deploy_x86_parser.add_argument('--localversion', help='Specify the LOCALVERSION string to choose the correct kernel to deploy')

    # Deploy to device command
    deploy_device_parser = subparsers.add_parser("deploy-device")
    deploy_device_parser.add_argument("--ip", required=True, help="IP address of the target device")
    deploy_device_parser.add_argument("--user", required=True, help="Username for accessing the target device")
    deploy_device_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')
    deploy_device_parser.add_argument('--localversion', help='Specify the LOCALVERSION string to choose the correct kernel to deploy')
    deploy_device_parser.add_argument('--kernel-only', action='store_true', help='Only deploy the kernel, skipping modules')

    # Deploy Debian package command
    deploy_debian_parser = subparsers.add_parser("deploy-debian")
    deploy_debian_parser.add_argument("--kernel-name", required=True, help="Name of the kernel subfolder to package")
    deploy_debian_parser.add_argument("--localversion", help="Specify the LOCALVERSION string to package the correct kernel")
    deploy_debian_parser.add_argument(
    "--dtb-name", default="tegra234-p3701-0000-p3737-0000",
    help="DTB filename prefix (without .dtb) to include in the package")

    # Deploy to Jetson command
    deploy_jetson_parser = subparsers.add_parser("deploy-jetson")
    deploy_jetson_parser.add_argument("--kernel-name", required=True, help="Name of the kernel subfolder to use for deployment")
    deploy_jetson_parser.add_argument("--ip", required=True, help="IP address of the Jetson device")
    deploy_jetson_parser.add_argument("--user", required=True, help="Username for accessing the Jetson device")
    deploy_jetson_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')
    deploy_jetson_parser.add_argument('--localversion', help='Specify the LOCALVERSION string to choose the correct kernel to deploy')
    deploy_jetson_parser.add_argument('--dtb', action='store_true', help='Sets the DTB compiled with the kernel to be the default')
    deploy_jetson_parser.add_argument('--kernel-only', action='store_true', help='Only deploy the kernel, skipping modules')

    # Deploy targeted modules command
    deploy_targeted_modules_parser = subparsers.add_parser("deploy-targeted-modules")
    deploy_targeted_modules_parser.add_argument("--kernel-name", required=True, help="Name of the kernel subfolder to use for deployment")
    deploy_targeted_modules_parser.add_argument("--ip", required=True, help="IP address of the target device")
    deploy_targeted_modules_parser.add_argument("--user", required=True, help="Username for accessing the target device")
    deploy_targeted_modules_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')

    args = parser.parse_args()

    # Print help if no command is provided
    if not args.command:
        parser.print_help()
        exit(1)

    if args.command == "deploy-x86":
        deploy_x86(dry_run=args.dry_run, localversion=args.localversion)
    elif args.command == "deploy-device":
        deploy_device(device_ip=args.ip, user=args.user, dry_run=args.dry_run, localversion=args.localversion, kernel_only=args.kernel_only)
    elif args.command == "deploy-jetson":
        deploy_jetson(kernel_name=args.kernel_name, device_ip=args.ip, user=args.user, dry_run=args.dry_run, localversion=args.localversion, dtb=args.dtb, kernel_only=args.kernel_only)
    elif args.command == "deploy-targeted-modules":
        deploy_targeted_modules(kernel_name=args.kernel_name, device_ip=args.ip, user=args.user, dry_run=args.dry_run)
    elif args.command == "deploy-debian":
        deb_file = create_deb_package(kernel_name=args.kernel_name, localversion=args.localversion, dtb_name=args.dtb_name)
    else:
        print("Failed to create Debian package.")


if __name__ == "__main__":
    main()

