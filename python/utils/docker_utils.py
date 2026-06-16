import os
import subprocess


def _repo_root() -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def docker_image_tag(jp7: bool = False) -> str:
    return "kernel_builder_jp7" if jp7 else "kernel_builder"


def docker_image_exists(tag: str) -> bool:
    return (
        subprocess.run(
            ["docker", "image", "inspect", tag],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        == 0
    )


def _kernel_builder_build_context() -> str:
    context = os.path.join(_repo_root(), "docker", "kernel-builder-context")
    os.makedirs(context, exist_ok=True)
    return context


def build_docker_image(rebuild=False, jp7=False):
    repo_root = _repo_root()
    dockerfile = os.path.join(repo_root, "Dockerfile.jp7" if jp7 else "Dockerfile")
    context = _kernel_builder_build_context()
    tag = docker_image_tag(jp7=jp7)

    build_command = ["docker", "build", "-f", dockerfile, "-t", tag]
    if rebuild:
        build_command.append("--no-cache")
    build_command.append(context)

    print(f"Running command: {' '.join(build_command)}")
    subprocess.run(build_command, cwd=repo_root, check=True)


def ensure_docker_image(jp7=False, rebuild=False, dry_run=False):
    tag = docker_image_tag(jp7=jp7)
    if docker_image_exists(tag) and not rebuild:
        return
    if dry_run:
        print(f"[Dry-run] Would build Docker image '{tag}'")
        return
    print(f"Docker image '{tag}' not found; building now (one-time setup)...")
    build_docker_image(rebuild=rebuild, jp7=jp7)


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
