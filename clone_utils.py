#!/usr/bin/env python3

import os

def clone_kernel(kernel_source_url, kernel_name, git_tag=None):
    # Clones the kernel source.
    kernel_dir = os.path.join("kernels", kernel_name, "kernel")
    if not os.path.exists(kernel_dir):
        clone_command = f"git clone {kernel_source_url} {kernel_dir}"
        print(f"Running command: {clone_command}")
        os.system(clone_command)
        if git_tag:
            os.chdir(kernel_dir)
            checkout_command = f"git checkout {git_tag}"
            print(f"Running command: {checkout_command}")
            os.system(checkout_command)
            os.chdir("..")
    else:
        print(f"Kernel directory {kernel_dir} already exists. Skipping clone.")

def clone_toolchain(toolchain_url, toolchain_name, git_tag=None):
    # Clones the toolchain source.
    toolchain_dir = os.path.join("toolchains", toolchain_name)
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
    kernel_base_dir = os.path.join("kernels", kernel_name)
    if not os.path.exists(kernel_base_dir):
        os.makedirs(kernel_base_dir)
    temp_overlays_dir = os.path.join(kernel_base_dir, "temp_overlays")
    if not os.path.exists(temp_overlays_dir):
        clone_command = f"git clone {overlays_url} {temp_overlays_dir}"
        print(f"Running command: {clone_command}")
        os.system(clone_command)
        if git_tag:
            os.chdir(temp_overlays_dir)
            checkout_command = f"git checkout {git_tag}"
            print(f"Running command: {checkout_command}")
            os.system(checkout_command)
            os.chdir("..")
        # Move the contents of temp_overlays to the kernel base directory
        for item in os.listdir(temp_overlays_dir):
            item_path = os.path.join(temp_overlays_dir, item)
            target_path = os.path.join(kernel_base_dir, item)
            os.rename(item_path, target_path)
        # Remove the temporary overlays directory
        os.rmdir(temp_overlays_dir)
    else:
        print(f"Overlays directory {temp_overlays_dir} already exists. Skipping clone.")

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

