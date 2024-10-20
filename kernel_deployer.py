import os
import argparse
import subprocess
import logging

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Function to deploy the kernel to an x86 host machine
def deploy_x86(output_dir):
    logging.info("Deploying kernel to x86 host machine...")

    # Define the paths for kernel and modules
    vmlinuz_path = os.path.join(output_dir, "vmlinuz")
    modules_path = os.path.join(output_dir, "lib/modules")

    # Copy kernel image to /boot and modules to /lib/modules
    subprocess.run(["sudo", "cp", vmlinuz_path, "/boot/"], check=True)
    subprocess.run(["sudo", "cp", "-r", modules_path, "/lib/modules/"], check=True)
    logging.info("Kernel deployed to x86 host machine successfully.")

# Function to deploy the kernel to a NVIDIA Jetson board
def deploy_jetson(output_dir, jetson_ip, jetson_user="ubuntu"):
    logging.info(f"Deploying kernel to NVIDIA Jetson board at {jetson_ip}...")

    # Define the paths for kernel, modules, and DTBs
    image_path = os.path.join(output_dir, "Image")
    dtb_path = os.path.join(output_dir, "*.dtb")
    modules_path = os.path.join(output_dir, "lib/modules")

    # Use scp to copy kernel image, DTBs, and modules to Jetson board
    subprocess.run(["scp", image_path, f"{jetson_user}@{jetson_ip}:/boot/"], check=True)
    subprocess.run(["scp", dtb_path, f"{jetson_user}@{jetson_ip}:/boot/"], check=True)
    subprocess.run(["scp", "-r", modules_path, f"{jetson_user}@{jetson_ip}:/lib/modules/"], check=True)
    logging.info("Kernel deployed to NVIDIA Jetson board successfully.")

# Function to deploy the kernel to a Raspberry Pi
def deploy_rpi(output_dir, rpi_ip, rpi_user="pi"):
    logging.info(f"Deploying kernel to Raspberry Pi at {rpi_ip}...")

    # Define the paths for kernel, modules, and DTBs
    kernel_img_path = os.path.join(output_dir, "Image")
    dtb_path = os.path.join(output_dir, "*.dtb")
    modules_path = os.path.join(output_dir, "lib/modules")

    # Use scp to copy kernel image, DTBs, and modules to Raspberry Pi
    subprocess.run(["scp", kernel_img_path, f"{rpi_user}@{rpi_ip}:/boot/kernel7.img"], check=True)
    subprocess.run(["scp", dtb_path, f"{rpi_user}@{rpi_ip}:/boot/"], check=True)
    subprocess.run(["scp", "-r", modules_path, f"{rpi_user}@{rpi_ip}:/lib/modules/"], check=True)
    logging.info("Kernel deployed to Raspberry Pi successfully.")

# Function to clone kernel source
def clone_kernel(kernel_source_url, kernel_dir, git_tag="master"):
    logging.info(f"Cloning kernel from {kernel_source_url} into {kernel_dir} with tag {git_tag}...")
    if not os.path.exists(kernel_dir):
        os.makedirs(kernel_dir)
    subprocess.run(["git", "clone", kernel_source_url, kernel_dir], check=True)
    subprocess.run(["git", "-C", kernel_dir, "checkout", git_tag], check=True)
    logging.info("Kernel cloned successfully.")

# Main function
def main():
    parser = argparse.ArgumentParser(
        description="Kernel Deployer for x86, NVIDIA Jetson, and Raspberry Pi devices",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )

    subparsers = parser.add_subparsers(dest="command", help="Available commands to deploy the kernel to different devices")

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

    # Sub-command for deploying to x86 host machine
    deploy_x86_parser = subparsers.add_parser(
        "deploy-x86",
        help="Deploy the compiled kernel to an x86 host machine",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    deploy_x86_parser.add_argument(
        "--output-dir",
        required=True,
        help="Directory on the host where the compiled kernel and modules are stored"
    )

    # Sub-command for deploying to NVIDIA Jetson board
    deploy_jetson_parser = subparsers.add_parser(
        "deploy-jetson",
        help="Deploy the compiled kernel to a NVIDIA Jetson board",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    deploy_jetson_parser.add_argument(
        "--output-dir",
        required=True,
        help="Directory on the host where the compiled kernel and modules are stored"
    )
    deploy_jetson_parser.add_argument(
        "--jetson-ip",
        required=True,
        help="IP address of the NVIDIA Jetson board"
    )
    deploy_jetson_parser.add_argument(
        "--jetson-user",
        default="ubuntu",
        help="Username for accessing the NVIDIA Jetson board (default: ubuntu)"
    )

    # Sub-command for deploying to Raspberry Pi
    deploy_rpi_parser = subparsers.add_parser(
        "deploy-rpi",
        help="Deploy the compiled kernel to a Raspberry Pi",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    deploy_rpi_parser.add_argument(
        "--output-dir",
        required=True,
        help="Directory on the host where the compiled kernel and modules are stored"
    )
    deploy_rpi_parser.add_argument(
        "--rpi-ip",
        required=True,
        help="IP address of the Raspberry Pi"
    )
    deploy_rpi_parser.add_argument(
        "--rpi-user",
        default="pi",
        help="Username for accessing the Raspberry Pi (default: pi)"
    )

    # Parse arguments
    args = parser.parse_args()

    if args.command == "clone-kernel":
        # Clone kernel source
        clone_kernel(args.kernel_source_url, args.kernel_dir, args.git_tag)
    elif args.command == "deploy-x86":
        # Deploy kernel to x86 host machine
        deploy_x86(args.output_dir)
    elif args.command == "deploy-jetson":
        # Deploy kernel to NVIDIA Jetson board
        deploy_jetson(args.output_dir, args.jetson_ip, args.jetson_user)
    elif args.command == "deploy-rpi":
        # Deploy kernel to Raspberry Pi
        deploy_rpi(args.output_dir, args.rpi_ip, args.rpi_user)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()

