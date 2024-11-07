import os
import subprocess

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
    # Stop and remove any containers using the 'kernel_builder' image
    try:
        # List all containers using the 'kernel_builder' image
        result = subprocess.run(
            ["docker", "ps", "-a", "-q", "--filter", "ancestor=kernel_builder"],
            capture_output=True,
            text=True,
            check=True
        )
        container_ids = result.stdout.strip().split("\n")

        # If there are containers found, stop and remove them
        if container_ids and container_ids[0] != "":
            for container_id in container_ids:
                print(f"Stopping container {container_id}")
                subprocess.run(["docker", "stop", container_id], check=True)
                print(f"Removing container {container_id}")
                subprocess.run(["docker", "rm", container_id], check=True)

    except subprocess.CalledProcessError as e:
        print(f"Error stopping or removing containers: {e}")

    # Now remove the image
    try:
        print("Removing Docker image 'kernel_builder'")
        subprocess.run(["docker", "rmi", "-f", "kernel_builder"], check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error removing image: {e}")

