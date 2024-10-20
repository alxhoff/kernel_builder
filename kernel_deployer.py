#!/usr/bin/env python3

import argparse
import os

def deploy_x86(output_dir):
    # Deploy kernel and modules to x86 host machine
    deploy_command = f"sudo cp {output_dir}/vmlinuz /boot/ && sudo cp -r {output_dir}/lib/modules/* /lib/modules/"
    os.system(deploy_command)

def deploy_device(output_dir, device_ip, user):
    # Deploy kernel and modules to a remote device (Jetson or Raspberry Pi)
    deploy_command = f"scp -r {output_dir}/* {user}@{device_ip}:/tmp/kernel_build/"
    os.system(deploy_command)
    # Remote commands to copy kernel and modules to appropriate locations
    remote_command = f"ssh {user}@{device_ip} 'sudo cp /tmp/kernel_build/vmlinuz /boot/ && sudo cp -r /tmp/kernel_build/lib/modules/* /lib/modules/'"
    os.system(remote_command)

def main():
    parser = argparse.ArgumentParser(description="Kernel Deployer Script")
    subparsers = parser.add_subparsers(dest="command")

    # Deploy to x86 host machine command
    deploy_x86_parser = subparsers.add_parser("deploy-x86")
    deploy_x86_parser.add_argument("--output-dir", required=True, help="Directory where the compiled kernel and modules are stored")

    # Deploy to Jetson or Raspberry Pi command
    deploy_device_parser = subparsers.add_parser("deploy-device")
    deploy_device_parser.add_argument("--output-dir", required=True, help="Directory where the compiled kernel and modules are stored")
    deploy_device_parser.add_argument("--ip", required=True, help="IP address of the target device")
    deploy_device_parser.add_argument("--user", required=True, help="Username for accessing the target device (default for Jetson: 'ubuntu', default for Raspberry Pi: 'pi')")

    args = parser.parse_args()

    # Print help if no command is provided
    if not args.command:
        parser.print_help()
        exit(1)

    if args.command == "deploy-x86":
        deploy_x86(output_dir=args.output_dir)
    elif args.command == "deploy-device":
        deploy_device(output_dir=args.output_dir, device_ip=args.ip, user=args.user)


if __name__ == "__main__":
    main()

