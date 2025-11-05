import os
import shutil
import subprocess

def clone_kernel(kernel_source_url, kernel_name, git_tag=None):
    # Clones the kernel source.
    kernel_base_dir = os.path.join("kernels", kernel_name, "kernel", "kernel")
    if not os.path.exists(kernel_base_dir):
        os.makedirs(kernel_base_dir)
        clone_command = f"git clone {kernel_source_url} {kernel_base_dir}"
        print(f"Running command: {clone_command}")
        os.system(clone_command)
        if git_tag:
            os.chdir(kernel_base_dir)
            checkout_command = f"git checkout {git_tag}"
            print(f"Running command: {checkout_command}")
            os.system(checkout_command)
            os.chdir("..")
    else:
        print(f"Kernel directory {kernel_base_dir} already exists. Skipping clone.")

def clone_toolchain(toolchain_url, toolchain_name, toolchain_version, git_tag=None):
    # Clones the toolchain source.
    toolchain_dir = os.path.join("toolchains", toolchain_name, toolchain_version)
    if not os.path.exists(toolchain_dir):
        clone_command = f"git clone {toolchain_url} {toolchain_dir}"
        print(f"Running command: {clone_command}")
        os.system(clone_command)
        if git_tag:
            os.chdir(toolchain_dir)
            checkout_command = f"git checkout {git_tag}"
            print(f"Running command: {checkout_command}")
            os.system(checkout_command)
            os.chdir("..")
    else:
        print(f"Toolchain directory {toolchain_dir} already exists. Skipping clone.")

def clone_overlays(overlays_url, kernel_name, git_tag=None):
    # Clones the overlays for the given kernel.
    kernel_base_dir = os.path.join("kernels", kernel_name, "kernel")
    if not os.path.exists(kernel_base_dir):
        os.makedirs(kernel_base_dir)

    temp_overlays_dir = os.path.join(kernel_base_dir, "temp_overlays")
    if os.path.exists(temp_overlays_dir):
        shutil.rmtree(temp_overlays_dir)

    # Clone overlays into a temporary directory
    clone_command = f"git clone {overlays_url} {temp_overlays_dir}"
    print(f"Running command: {clone_command}")
    subprocess.run(clone_command, shell=True, check=True)

    if git_tag:
        checkout_command = f"git -C {temp_overlays_dir} checkout {git_tag}"
        print(f"Running command: {checkout_command}")
        subprocess.run(checkout_command, shell=True, check=True)

    # Ensure the temporary directory exists before attempting to move files
    if os.path.isdir(temp_overlays_dir):
        # Move all contents from the temporary directory to the overlays directory, including the .git folder
        for item in os.listdir(temp_overlays_dir):
            s = os.path.join(temp_overlays_dir, item)
            d = os.path.join(kernel_base_dir, item)
            if os.path.isdir(s):
                if os.path.exists(d):
                    shutil.rmtree(d)
                shutil.copytree(s, d)
            else:
                shutil.copy2(s, d)
        # Remove the temporary directory
        shutil.rmtree(temp_overlays_dir)
    else:
        print(f"Temporary overlays directory {temp_overlays_dir} does not exist. Skipping move.")

def clone_device_tree(device_tree_url, kernel_name, git_tag=None):
    # Clones the device tree hardware repository for the given kernel.
    kernel_base_dir = os.path.join("kernels", kernel_name)
    device_tree_dir = os.path.join(kernel_base_dir, "hardware")
    if not os.path.exists(device_tree_dir):
        clone_command = f"git clone {device_tree_url} {device_tree_dir}"
        print(f"Running command: {clone_command}")
        os.system(clone_command)
        if git_tag:
            os.chdir(device_tree_dir)
            checkout_command = f"git checkout {git_tag}"
            print(f"Running command: {checkout_command}")
            os.system(checkout_command)
            os.chdir("..")
    else:
        print(f"Device tree directory {device_tree_dir} already exists. Skipping clone.")

