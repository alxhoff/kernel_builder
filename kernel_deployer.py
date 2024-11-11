#!/usr/bin/env python3

import argparse
import os
import subprocess

def deploy_x86(dry_run=False):
    # Deploys the compiled kernel to an x86 host machine.
    modules_base_dir = os.path.join("kernels", "compiled", "modules")
    kernel_version = os.listdir(os.path.join(modules_base_dir, "lib", "modules"))[0]
    modules_dir = os.path.join(modules_base_dir, "lib", "modules", kernel_version)
    kernel_image = os.path.join("kernels", "compiled", "vmlinuz")

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

def deploy_device(device_ip, user, dry_run=False):
    # Deploys the compiled kernel to a remote device via SSH and SCP.
    modules_base_dir = os.path.join("kernels", "compiled", "modules")
    kernel_version = os.listdir(os.path.join(modules_base_dir, "lib", "modules"))[0]
    modules_dir = os.path.join(modules_base_dir, "lib", "modules", kernel_version)
    kernel_image = os.path.join("kernels", "compiled", "vmlinuz")

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

def deploy_jetson(kernel_name, device_ip, user, dry_run=False):
    # Deploys the compiled kernel to a remote Jetson device via SCP.
    kernel_dir = os.path.join("kernels", kernel_name, "kernel", "kernel")

    # Define paths for deployment
    kernel_image = os.path.join(kernel_dir, "arch/arm64/boot/Image")
    dtb_file = os.path.join(kernel_dir, "arch/arm64/boot/dts/nvidia/tegra234-p3701-0000-p3737-0000.dtb")
    modules_base_dir = os.path.join("kernels", kernel_name, "modules")
    kernel_version = os.listdir(os.path.join(modules_base_dir, "lib", "modules"))[0]
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
    extract_command = f"ssh {user}@{device_ip} 'mkdir -p /tmp/modules && tar -xzf /tmp/{kernel_version}.tar.gz -C /tmp/modules'"
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
    move_command = f"ssh root@{device_ip} 'mv /tmp/{os.path.basename(dtb_file)} /boot/dtb/tegra234-p3701-0000-p3737-0000.dtb'"
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
    depmod_command = f"ssh root@{device_ip} 'sudo depmod {kernel_version}'"
    print(f"Running depmod on the target device: {depmod_command}")
    if not dry_run:
        subprocess.run(depmod_command, shell=True, check=True)

def main():
    parser = argparse.ArgumentParser(description="Kernel Deployer Script")
    subparsers = parser.add_subparsers(dest="command")

    # Deploy to x86 command
    deploy_x86_parser = subparsers.add_parser("deploy-x86")
    deploy_x86_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')

    # Deploy to device command
    deploy_device_parser = subparsers.add_parser("deploy-device")
    deploy_device_parser.add_argument("--ip", required=True, help="IP address of the target device")
    deploy_device_parser.add_argument("--user", required=True, help="Username for accessing the target device")
    deploy_device_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')

    # Deploy to Jetson command
    deploy_jetson_parser = subparsers.add_parser("deploy-jetson")
    deploy_jetson_parser.add_argument("--kernel-name", required=True, help="Name of the kernel subfolder to use for deployment")
    deploy_jetson_parser.add_argument("--ip", required=True, help="IP address of the Jetson device")
    deploy_jetson_parser.add_argument("--user", required=True, help="Username for accessing the Jetson device")
    deploy_jetson_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')

    args = parser.parse_args()

    # Print help if no command is provided
    if not args.command:
        parser.print_help()
        exit(1)

    if args.command == "deploy-x86":
        deploy_x86(dry_run=args.dry_run)
    elif args.command == "deploy-device":
        deploy_device(device_ip=args.ip, user=args.user, dry_run=args.dry_run)
    elif args.command == "deploy-jetson":
        deploy_jetson(kernel_name=args.kernel_name, device_ip=args.ip, user=args.user, dry_run=args.dry_run)

if __name__ == "__main__":
    main()

