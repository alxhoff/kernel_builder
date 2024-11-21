#!/usr/bin/env python3

import argparse
import os
import subprocess

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

def deploy_device(device_ip, user, dry_run=False, localversion=None):
    # Deploys the compiled kernel to a remote device via SSH and SCP.
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

    # Copy the kernel image to the remote device
    remote_boot_dir = f"{user}@{device_ip}:/boot"
    print(f"Copying {kernel_image} to {remote_boot_dir}")
    if not dry_run:
        subprocess.run(["scp", kernel_image, remote_boot_dir], check=True)

    # Copy the modules to the remote device
    remote_modules_dir = f"{user}@{device_ip}:/lib/modules/{kernel_version}"
    print(f"Copying modules from {modules_dir} to {remote_modules_dir}")
    if not dry_run:
        subprocess.run(["scp", "-r", modules_dir, remote_modules_dir], check=True)

def deploy_jetson(kernel_name, device_ip, user, dry_run=False, localversion=None, dtb=False):
    # Deploys the compiled kernel to a remote Jetson device via SCP.
    modules_base_dir = os.path.join("kernels", kernel_name, "modules")
    kernel_versions = os.listdir(os.path.join(modules_base_dir, "lib", "modules"))
    kernel_version = next((version for version in kernel_versions if localversion in version), kernel_versions[0]) if localversion else kernel_versions[0]

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
    # Search in the entire kernel source including any overlays
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

    # Locate the compiled .ko files for the specified modules
    compiled_modules = locate_compiled_modules(kernel_name, target_modules)

    if not compiled_modules:
        print("No compiled modules found to deploy.")
        return

    # Create a temporary archive of the compiled .ko files
    modules_archive = "/tmp/targeted_modules.tar.gz"
    print(f"Compressing compiled modules into {modules_archive}")
    if not dry_run:
        with open("/tmp/compiled_modules.txt", "w") as f:
            for module_path in compiled_modules:
                f.write(module_path + "\n")
        subprocess.run(["tar", "-czf", modules_archive, "-T", "/tmp/compiled_modules.txt"], check=True)

    # Copy the compressed modules archive to /tmp on the remote device
    print(f"Copying {modules_archive} to /tmp on remote device")
    if not dry_run:
        subprocess.run(["scp", modules_archive, f"{user}@{device_ip}:/tmp/"], check=True)

    # Extract the modules archive on the remote device
    kernel_version = subprocess.check_output(f"ssh {user}@{device_ip} 'uname -r'", shell=True).strip().decode('utf-8')
    extract_command = f"ssh root@{device_ip} 'mkdir -p /tmp/targeted_modules && tar -xzf /tmp/targeted_modules.tar.gz -C /tmp/targeted_modules'"
    print(f"Extracting targeted modules on remote device: {extract_command}")
    if not dry_run:
        subprocess.run(extract_command, shell=True, check=True)

    # Copy the extracted modules to the appropriate location under /lib/modules/<kernel_version>/
    move_command = f"ssh root@{device_ip} 'cp /tmp/targeted_modules/*.ko /lib/modules/{kernel_version}/extra/'"
    print(f"Moving compiled kernel modules to /lib/modules/{kernel_version}/extra on remote device: {move_command}")
    if not dry_run:
        subprocess.run(move_command, shell=True, check=True)

    # Run depmod to refresh module dependencies
    depmod_command = f"ssh root@{device_ip} 'depmod -a'"
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

    # Deploy to Jetson command
    deploy_jetson_parser = subparsers.add_parser("deploy-jetson")
    deploy_jetson_parser.add_argument("--kernel-name", required=True, help="Name of the kernel subfolder to use for deployment")
    deploy_jetson_parser.add_argument("--ip", required=True, help="IP address of the Jetson device")
    deploy_jetson_parser.add_argument("--user", required=True, help="Username for accessing the Jetson device")
    deploy_jetson_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')
    deploy_jetson_parser.add_argument('--localversion', help='Specify the LOCALVERSION string to choose the correct kernel to deploy')
    deploy_jetson_parser.add_argument('--dtb', help='Specify a custom Device Tree Blob (DTB) file to use for deployment')

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
        deploy_device(device_ip=args.ip, user=args.user, dry_run=args.dry_run, localversion=args.localversion)
    elif args.command == "deploy-jetson":
        deploy_jetson(kernel_name=args.kernel_name, device_ip=args.ip, user=args.user, dry_run=args.dry_run, localversion=args.localversion, dtb=args.dtb)
    elif args.command == "deploy-targeted-modules":
        deploy_targeted_modules(kernel_name=args.kernel_name, device_ip=args.ip, user=args.user, dry_run=args.dry_run)

if __name__ == "__main__":
    main()

