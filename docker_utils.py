import os

def build_docker_image(rebuild=False):
    # Command to build/rebuild the Docker image.
    build_command = "docker build -t kernel_builder ."
    if rebuild:
        build_command += " --no-cache"
    print(f"Running command: {build_command}")
    os.system(build_command)

def inspect_docker_image(output_dir="output"):
    # Opens a bash shell inside the Docker container for inspection
    kernel_dir_abs = os.path.abspath("kernels")
    toolchain_dir_abs = os.path.abspath("toolchains")
    output_dir_abs = os.path.abspath(output_dir)

    volume_args = f"-v {kernel_dir_abs}:/builder/kernels -v {output_dir_abs}:/builder/output"
    if os.path.exists(toolchain_dir_abs):
        volume_args += f" -v {toolchain_dir_abs}:/builder/toolchains"

    inspect_command = f"docker run --rm -it {volume_args} -w /builder kernel_builder /bin/bash"
    print(f"Running command: {inspect_command}")
    os.system(inspect_command)

def cleanup_docker():
    # Removes the Docker image and prunes unused containers
    cleanup_command = "docker rmi kernel_builder && docker container prune -f"
    print(f"Running command: {cleanup_command}")
    os.system(cleanup_command)

