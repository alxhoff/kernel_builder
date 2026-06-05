#!/usr/bin/env bash
set -euo pipefail

# This script can be run inside a Docker container to provide a consistent environment.
# If the --docker flag is provided, the script will re-launch itself inside a
# pre-configured Docker container.

DOCKER_FLAG_PRESENT=0
# We do a quick pre-scan for the --docker flag.
# This is because the script consumes arguments in the main parsing loop,
# and we need to act on --docker before that happens.
for arg in "$@"; do
    if [[ "$arg" == "--docker" ]]; then
        DOCKER_FLAG_PRESENT=1
        break
    fi
done

# If --docker is present, set up the environment and re-launch.
if [[ "$DOCKER_FLAG_PRESENT" -eq 1 ]]; then
    # Ensure the script is run with sudo for docker commands and host setup.
    if [[ "$EUID" -ne 0 ]]; then
        echo "This script must be run with sudo when using the --docker flag." >&2
        exit 1
    fi

    # --- Host Dependency Installation for Docker ---
    echo "Checking for and installing host dependencies for cross-architecture container support..."

    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS=$NAME
    else
        echo "Cannot determine the operating system." >&2
        exit 1
    fi

    if [[ "$OS" == "Ubuntu" || "$OS" == "Debian GNU/Linux" ]]; then
        if ! dpkg -l | grep -q "qemu-user-static" || ! dpkg -l | grep -q "binfmt-support"; then
            echo "Installing QEMU and binfmt support for Debian/Ubuntu..."
            apt-get update
            apt-get install -y qemu-user-static binfmt-support
        else
            echo "QEMU and binfmt support are already installed."
        fi
    elif [[ "$OS" == "Arch Linux" || "$OS" == "Manjaro Linux" ]]; then
        if ! pacman -Q | grep -q "qemu-user-static" || ! pacman -Q | grep -q "binfmt-support"; then
            echo "Installing QEMU and binfmt support for Arch Linux..."
            pacman -Syu --noconfirm qemu-user-static qemu-user-static-binfmt
        else
            echo "QEMU and binfmt support are already installed."
        fi
    else
        echo "Unsupported operating system for automatic dependency installation: $OS" >&2
        exit 1
    fi

    # Register QEMU handlers with the kernel for ARM64 emulation.
    echo "Registering QEMU handlers with the kernel..."
    docker run --rm --privileged multiarch/qemu-user-static --reset -p yes > /dev/null

    # --- Docker Image and Container Setup ---
    SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
    IMAGE="ubuntu:22.04"
    CONTAINER_NAME="rootfs_flasher_setup"
    DOCKER_TAG="jetson_builder:latest"

    # Build the 'jetson_builder' Docker image if it doesn't already exist.
    if [[ "$(docker images -q "$DOCKER_TAG" 2> /dev/null)" == "" ]]; then
        echo "Building the Docker image '$DOCKER_TAG'..."
        docker pull "$IMAGE"
        # This Dockerfile mirrors the one used by setup_tegra_package.sh --docker.
        docker build --dns=8.8.8.8 --dns=8.8.4.4 -t "$DOCKER_TAG" - <<EOF
        FROM $IMAGE
        RUN apt-get update && apt-get install -y \
            sudo \
            tar \
            bzip2 \
            git \
            wget \
            curl \
            openssh-client \
            iputils-ping \
            docker.io \
            jq \
            qemu-user-static \
            binfmt-support \
            unzip \
            build-essential \
            kmod \
            flex \
            bison \
            libelf-dev \
            bc \
            dwarves \
            ccache \
            libncurses5-dev \
            vim-common \
            rsync \
            zlib1g \
            libssl-dev
EOF
    else
        echo "Using existing Docker image: $DOCKER_TAG"
    fi

    # Clean up any previous container with the same name.
    if docker ps -a --format '{{.Names}}' | grep -qw "$CONTAINER_NAME"; then
        echo "Removing existing container: $CONTAINER_NAME"
        docker rm -f "$CONTAINER_NAME"
    fi

    # Reconstruct arguments, filtering out --docker and handling local file paths.
    # A temporary directory is created to hold copies of files like certificates,
    # making them available inside the Docker container.
    TEMP_ASSETS_DIR=$(mktemp -d -p "$SCRIPT_DIR" "docker_assets.XXXXXX")
    trap 'rm -rf "$TEMP_ASSETS_DIR"' EXIT # Ensure cleanup on script exit

    ARGS=()
    # Use a state machine to parse arguments that take a value.
    next_arg_is_path_for=""
    for arg in "$@"; do
        if [[ -n "$next_arg_is_path_for" ]]; then
            host_path="$arg"
            # Ensure the file exists on the host.
            if [[ ! -f "$host_path" ]]; then
                echo "Error: File not found for $next_arg_is_path_for: $host_path" >&2
                exit 1
            fi

            filename=$(basename "$host_path")
            cp "$host_path" "$TEMP_ASSETS_DIR/"

            # The path inside the container will be relative to the workspace.
            container_path="./$(basename "$TEMP_ASSETS_DIR")/$filename"
            ARGS+=("$(printf '%q' "$container_path")")

            next_arg_is_path_for="" # Reset for the next argument.
        else
            case "$arg" in
                --docker)
                    # The --docker flag is consumed and not passed into the container.
                    ;;
                --crt|--key|--zip)
                    # These flags expect a file path as the next argument.
                    ARGS+=("$(printf '%q' "$arg")")
                    next_arg_is_path_for="$arg"
                    ;;
                *)
                    # Other arguments are passed through as-is.
                    ARGS+=("$(printf '%q' "$arg")")
                    ;;
            esac
        fi
    done

    # If an option like --crt was given but was the last argument.
    if [[ -n "$next_arg_is_path_for" ]]; then
        echo "Error: Missing path for $next_arg_is_path_for option." >&2
        exit 1
    fi

    # The command to execute inside the container is this script itself.
    CONTAINER_CMD="./$(basename "${BASH_SOURCE[0]}") ${ARGS[*]}"

    echo "Re-launching script inside Docker container. All subsequent output will be from the container."
    # Run the container.
    # --privileged is crucial for USB device access needed for flashing.
    # --network=host allows scp/ping to other devices on the local network.
    # -it provides an interactive tty for prompts.
    docker run --rm -it \
        --name "$CONTAINER_NAME" \
        --privileged \
        --network=host \
        -v "$SCRIPT_DIR:/workspace" \
        -v "/var/run/docker.sock:/var/run/docker.sock" \
        -w "/workspace" \
        -e HOME="/workspace" \
        -e SUDO_USER="${SUDO_USER-}" \
        "$DOCKER_TAG" \
        /bin/bash -c "$CONTAINER_CMD"

    # Exit the host script. The exit code of the container will be propagated.
    exit $?
fi



# --- Config ---
# SSH access for AWX uses cartken-jetson-sshd-v2 (port 8612) with backend-signed
# host certificates and a backend-issued user CA. v1 (port 22, password +
# legacy authorized_keys) is being phased out; this script targets v2-from-
# first-boot:
#   1. We pre-populate /etc/ssh/cartken_sshd/{ssh_host_cartken_ed25519_key,
#      ssh_host_cartken_ed25519_key.pub, ssh_host_cartken_ed25519_key-cert.pub,
#      ssh_user_ca.pub, authorized_principals[, _local]} in the rootfs.
#   2. The chroot step (see chroot_install_cartken.txt) installs the
#      cartken-jetson-sshd-v2 deb so the unit is enabled before flash.
# The provisioning therefore has to run BEFORE the chroot runs, otherwise the
# v2 deb's postinst would land on an empty config dir.
# AWX's update-jetson role (common/robot-sshd-config-update) re-runs the same
# provisioning every pass to refresh the (short-lived) host certificate.
REMOTE_PATH="/etc/openvpn/cartken/2.0/crt"
INTERFACES=(wlan0 modem1 modem2 modem3)
CERT_PATH=""
KEY_PATH=""

# --- Help function ---
show_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

This script prepares and flashes a Jetson device using a local BSP rootfs.
It can optionally pull certs and inject configuration for a specific robot.

Options:
  --target-bsp <version> Target JetPack version (e.g., 5.1.2). (Required)
  --soc <soc>            Target SoC platform: 'orin' or 'xavier'. Default: orin.
  --robot-number <id>    Set robot number and fetch certs + inject hostname/env.
  --docker               Run the script inside a Docker container for a consistent environment.
  --dry-run              Simulate connectivity and cert fetch without execution.
  --password             Password for pulling VPN credentials.
  --skip-vpn	    Skips pulling and updaing the VPN certificates
  --crt                  Provide the VPN certificate directly.
  --key                  Provide the VPN key directly.
  --zip                  Provide a zip file containing the VPN certificate and key.
  --l4t-dir <path>       Specify the L4T directory path. (Optional, default is derived from TARGET_BSP)
  --env <env>            Cartken backend environment to sign SSH CA material against
                         (production | staging | sandbox). Default: production.
  --skip-ssh-ca          Do not provision /etc/ssh/cartken_sshd/. The
                         cartken-jetson-sshd-v2 deb is still installed by the
                         chroot, so cartken-sshd will fail to start on first
                         boot until AWX update-jetson writes the missing
                         files. Use only when the SSH CA backend is
                         unreachable.
  --refresh-ssh-ca-only  Refresh only /etc/ssh/cartken_sshd/ material
                         (host key, host cert, user CA, principals) and exit.
                         Skips VPN copy, package/tag refresh, chroot, hostname
                         updates, and flashing.
  --host-cert-validity <duration>
                         Validity for the signed host certificate (e.g. 24h, 48h, 7d).
                         AWX update-jetson re-signs the cert on first connect.
                         Default: 7d.
  --tag <tag>            Refresh the cartken packages baked into the rootfs from
                         the named gitlab tag (e.g. v7.5.0-sshca8) before the
                         chroot runs. Lets you re-flash an existing rootfs at a
                         newer tag without re-running setup_tegra_package.sh.
                         Requires --access-token. If the tag does not contain
                         cartken-jetson-sshd-v2*.deb the script aborts before
                         touching the rootfs further.
  --access-token <tok>   GitLab access token used by get_packages.sh when --tag
                         is set. Ignored otherwise.
  --clean-rootfs         Wipe the existing rootfs and re-run setup_tegra_package.sh
                         from scratch (BSP extract + apply_binaries + base chroot)
                         before continuing with the per-robot flow. Use when the
                         existing rootfs has accumulated stale artefacts (e.g.
                         cartken packages dropped from the repo, files written by
                         older versions of these scripts) and you want a clean
                         baseline without manually rebuilding kernel/drivers.
                         Requires --tag and --access-token. Skips kernel/display
                         driver/pinmux rebuilds for speed; if you also need those,
                         re-run setup_tegra_package.sh manually instead.
  -h, --help             Show this help message and exit.

Examples:
  $0 --target-bsp 5.1.2 --soc orin --robot-number 302
  $0 --target-bsp 5.1.5 --soc orin --robot-number 302 --env staging
  $0 --target-bsp 5.1.5 --soc orin --robot-number 302 --env staging \\
     --tag v7.5.0-sshca8 --access-token glpat-xxx

Notes:
- This script requires a local BSP directory (e.g., 5.1.2/Linux_for_Tegra).
- This script must be run as root.
- Provisioning SSH CA material uses cartken-dev. Run
    cartken account login <env>
  in your normal user shell first; the script invokes cartken via sudo -u "\$SUDO_USER".
EOF
}

# --- Parse args ---
TARGET_BSP="5.1.5"
SOC="orin"
ROBOT_NUMBER=""
DRY_RUN=0
PASSWORD=""
SKIP_VPN=0
ZIP_PATH=""
L4T_DIR_ARG=""
BACKEND_ENV="production"
SKIP_SSH_CA=0
REFRESH_SSH_CA_ONLY=0
HOST_CERT_VALIDITY="7d"
TAG=""
ACCESS_TOKEN=""
CLEAN_ROOTFS=0

run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[dry-run] $@"
    else
        eval "$@"
    fi
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --target-bsp)
      TARGET_BSP="$2"
      shift 2
      ;;
    --soc)
      SOC="$2"
      shift 2
      ;;
    --robot-number)
      ROBOT_NUMBER="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
	--skip-vpn)
	  SKIP_VPN=1
	  shift
	  ;;
    --password)
      PASSWORD="$2"
      shift 2
      ;;
    --crt)
      CERT_PATH="$2"
      shift 2
      ;;
    --key)
      KEY_PATH="$2"
      shift 2
      ;;
    --zip)
      ZIP_PATH="$2"
      shift 2
      ;;
    --l4t-dir)
      L4T_DIR_ARG="$2"
      shift 2
      ;;
    --env)
      BACKEND_ENV="$2"
      shift 2
      ;;
    --skip-ssh-ca)
      SKIP_SSH_CA=1
      shift
      ;;
    --refresh-ssh-ca-only)
      REFRESH_SSH_CA_ONLY=1
      shift
      ;;
    --host-cert-validity)
      HOST_CERT_VALIDITY="$2"
      shift 2
      ;;
    --tag)
      TAG="$2"
      shift 2
      ;;
    --access-token)
      ACCESS_TOKEN="$2"
      shift 2
      ;;
    --clean-rootfs)
      CLEAN_ROOTFS=1
      shift
      ;;
    *)
      echo "Unknown option: $1"; exit 1
      ;;
  esac
done

if [[ -n "$TAG" && -z "$ACCESS_TOKEN" ]]; then
  echo "Error: --tag '$TAG' requires --access-token <gitlab token>." >&2
  exit 1
fi

if [[ "$CLEAN_ROOTFS" -eq 1 && ( -z "$TAG" || -z "$ACCESS_TOKEN" ) ]]; then
  echo "Error: --clean-rootfs requires --tag and --access-token (passed through to setup_tegra_package.sh)." >&2
  exit 1
fi

if [[ "$REFRESH_SSH_CA_ONLY" -eq 1 && "$SKIP_SSH_CA" -eq 1 ]]; then
  echo "Error: --refresh-ssh-ca-only cannot be combined with --skip-ssh-ca." >&2
  exit 1
fi

if [[ "$REFRESH_SSH_CA_ONLY" -eq 1 && -z "${ROBOT_NUMBER-}" ]]; then
  echo "Error: --refresh-ssh-ca-only requires --robot-number." >&2
  exit 1
fi

case "$BACKEND_ENV" in
  production|staging|sandbox|prod|localhost) ;;
  *)
    echo "Error: --env must be one of production|staging|sandbox (got '$BACKEND_ENV')." >&2
    exit 1
    ;;
esac
[[ "$BACKEND_ENV" == "prod" ]] && BACKEND_ENV="production"

case "$SOC" in
  orin|xavier) ;;
  *)
    echo "Error: --soc must be 'orin' or 'xavier' (got '$SOC')." >&2
    exit 1
    ;;
esac



# --- Validate required args ---
if [[ "$REFRESH_SSH_CA_ONLY" -eq 0 ]]; then
  if [[ -z "${ROBOT_NUMBER-}" && -z "${CERT_PATH-}" && -z "${KEY_PATH-}" && -z "${ZIP_PATH-}" && "$SKIP_VPN" -eq 0 ]]; then
      echo "Error: Either --robot-number, --crt/--key, --zip or --skip-vpn must be provided if not skipping VPN." >&2
      show_help
      exit 1
  fi
fi
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root." >&2
    exit 1
fi

# --- Set up paths ---
SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "$L4T_DIR_ARG" ]]; then
  L4T_DIR="$L4T_DIR_ARG"
else
  # New canonical location is bsp/<version>/Linux_for_Tegra/. Fall back to
  # the legacy <version>/Linux_for_Tegra/ if a user still has a BSP from
  # before the bsp/ relocation, so we don't strand them.
  L4T_DIR="$SCRIPT_DIRECTORY/bsp/$TARGET_BSP/Linux_for_Tegra"
  if [[ ! -d "$L4T_DIR" && -d "$SCRIPT_DIRECTORY/$TARGET_BSP/Linux_for_Tegra" ]]; then
    L4T_DIR="$SCRIPT_DIRECTORY/$TARGET_BSP/Linux_for_Tegra"
  fi
fi
ROOTFS_PATH="$L4T_DIR/rootfs"
FLASH_SCRIPT="$L4T_DIR/flash_jetson_ALL_sdmmc_partition_qspi.sh"
CHROOT_CMD_FILE="$SCRIPT_DIRECTORY/chroot_install_cartken.txt"

# --- Check for L4T directory ---
if [[ ! -d "$L4T_DIR" ]]; then
  echo "Error: Tegra directory '$L4T_DIR' not found." >&2
  echo "Please ensure the BSP for $TARGET_BSP is correctly located." >&2
  exit 1
fi

# --- Optional: wipe the rootfs and re-run setup_tegra_package.sh ---
# Use case: long-lived rootfs has accumulated stale artefacts (debs dropped
# from the repo, files written by older versions of our scripts, etc.) and
# we want to converge on a known state without hand-debugging dpkg's
# database. setup_tegra_package.sh re-extracts the BSP rootfs tarball,
# re-applies NVIDIA binaries, and re-runs the base chroot (which now does a
# full cartken-* purge before installing). Kernel/display/pinmux rebuilds
# are skipped for speed; pass them up to setup_tegra_package.sh manually if
# you actually need to rebuild those.
if [[ "$CLEAN_ROOTFS" -eq 1 ]]; then
  TEGRA_PKG_SH="$SCRIPT_DIRECTORY/setup_tegra_package.sh"
  if [[ ! -x "$TEGRA_PKG_SH" ]]; then
    echo "Error: $TEGRA_PKG_SH not found or not executable." >&2
    exit 1
  fi
  echo "--clean-rootfs: wiping $ROOTFS_PATH and re-running setup_tegra_package.sh (tag=$TAG, jetpack=$TARGET_BSP)..."
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] rm -rf $ROOTFS_PATH"
    echo "[dry-run] $TEGRA_PKG_SH --jetpack $TARGET_BSP --access-token <redacted> --tag $TAG --soc $SOC --skip-kernel-build --skip-display-driver-build --skip-pinmux"
  else
    rm -rf "$ROOTFS_PATH"
    "$TEGRA_PKG_SH" \
      --jetpack "$TARGET_BSP" \
      --access-token "$ACCESS_TOKEN" \
      --tag "$TAG" \
      --soc "$SOC" \
      --skip-kernel-build \
      --skip-display-driver-build \
      --skip-pinmux
    echo "--clean-rootfs: rootfs rebuilt; continuing with per-robot setup."
  fi
fi

# --- Install dependencies ---
if grep -qi "arch" /etc/os-release; then
  DISTRO="arch"
elif grep -qi "ubuntu" /etc/os-release; then
  DISTRO="ubuntu"
else
  DISTRO="unknown"
fi

if [[ "$DISTRO" == "ubuntu" ]]; then
   sudo apt-get update
   sudo apt-get install -y qemu-user-static libxml2-utils sshpass curl unzip
fi

# Resolve the absolute path to `cartken` under $SUDO_USER. We can't rely on
# PATH inside the script: when run via `sudo`, secure_path strips ~/.local/bin
# (where pip-user installs of cartken-dev typically land), and nested
# `sudo -u $SUDO_USER` doesn't load the user's login profile either. We probe
# common locations + a login shell as a fallback, then use the resulting
# absolute path for every subsequent invocation.
resolve_cartken_bin() {
  if [[ -z "${SUDO_USER:-}" ]]; then
    return 1
  fi
  local user_home
  user_home="$(getent passwd "$SUDO_USER" | cut -d: -f6 || true)"
  if [[ -n "$user_home" && -x "$user_home/.local/bin/cartken" ]]; then
    echo "$user_home/.local/bin/cartken"
    return 0
  fi
  local found
  found="$(sudo -u "$SUDO_USER" -i -- bash -c 'command -v cartken' 2>/dev/null || true)"
  if [[ -n "$found" && -x "$found" ]]; then
    echo "$found"
    return 0
  fi
  for candidate in /usr/local/bin/cartken /usr/bin/cartken; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

# --- Pull certs and maybe chroot ---
if [[ -n "$ROBOT_NUMBER" ]]; then
  LOCAL_DEST="$ROOTFS_PATH/etc/openvpn/cartken/2.0/crt"
  if [[ "$REFRESH_SSH_CA_ONLY" -eq 0 ]]; then
    run mkdir -p "$LOCAL_DEST"
  fi

  if [[ -n "$ZIP_PATH" && "$REFRESH_SSH_CA_ONLY" -eq 0 ]]; then
    TEMP_DIR=$(mktemp -d)
    if [ -d "$TEMP_DIR" ]; then
        trap 'rm -rf "$TEMP_DIR"' EXIT
    else
        echo "Failed to create temp directory" >&2
        exit 1
    fi
    echo "Extracting certs from $ZIP_PATH..."
    if ! unzip -j "$ZIP_PATH" -d "$TEMP_DIR"; then
        echo "Failed to unzip $ZIP_PATH" >&2
        exit 1
    fi

    CERT_PATH=$(find "$TEMP_DIR" -name "*.crt" | head -n 1)
    KEY_PATH=$(find "$TEMP_DIR" -name "*.key" | head -n 1)

    if [[ -z "$CERT_PATH" || -z "$KEY_PATH" ]]; then
      echo "Error: .crt or .key file not found in the zip archive." >&2
      exit 1
    fi
  fi

  NEED_CERT=0
  NEED_KEY=0

  if [[ -n "$CERT_PATH" && "$REFRESH_SSH_CA_ONLY" -eq 0 ]]; then
      echo "Copying local cert from $CERT_PATH..."
      run cp "$CERT_PATH" "$LOCAL_DEST/robot.crt"
  else
      NEED_CERT=1
  fi

  if [[ -n "$KEY_PATH" && "$REFRESH_SSH_CA_ONLY" -eq 0 ]]; then
      echo "Copying local key from $KEY_PATH..."
      run cp "$KEY_PATH" "$LOCAL_DEST/robot.key"
  else
      NEED_KEY=1
  fi

  if [[ "$REFRESH_SSH_CA_ONLY" -eq 1 ]]; then
    echo "--refresh-ssh-ca-only: skipping VPN cert handling."
  elif [[ "$SKIP_VPN" -eq 1 ]]; then
    if [[ "$NEED_CERT" -eq 1 && "$NEED_KEY" -eq 0 ]] || [[ "$NEED_CERT" -eq 0 && "$NEED_KEY" -eq 1 ]]; then
      echo "Error: only one of --crt / --key was provided alongside --skip-vpn." >&2
      echo "Either pass both, or drop --crt/--key entirely to skip VPN setup." >&2
      exit 1
    fi
    echo "--skip-vpn active, skipping VPN certificate copy."
  elif [[ "$NEED_CERT" -eq 1 || "$NEED_KEY" -eq 1 ]]; then
    if [[ -z "${CARTKEN_BIN:-}" ]]; then
      CARTKEN_BIN="$(resolve_cartken_bin || true)"
    fi
    if [[ -z "$CARTKEN_BIN" ]]; then
      echo "Error: 'cartken' could not be found for user '$SUDO_USER'; needed to fetch robot IPs." >&2
      exit 1
    fi
    echo "Fetching robot IPs via $CARTKEN_BIN..."
    # -H so the inner cartken process sees HOME=/home/$SUDO_USER, otherwise
    # Python's user-site (~/.local/lib/python*/site-packages) isn't found and
    # `cartken` fails with ModuleNotFoundError when launched via outer sudo.
    ROBOT_IPS=$(sudo -u "$SUDO_USER" -H -E -- "$CARTKEN_BIN" r ip "$ROBOT_NUMBER" 2>&1)
    echo "$ROBOT_IPS"
    ROBOT_IP=""

    while read -r iface ip _; do
      for match_iface in "${INTERFACES[@]}"; do
        if [[ "$iface" == "$match_iface" ]]; then
          echo "Testing $iface ($ip)..."
          if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "[dry-run] Would ping $ip"
            ROBOT_IP="$ip"
            break 2
          elif ping -4 -c 1 -W 2 "$ip" >/dev/null 2>&1; then
            echo "Selected $iface ($ip) as reachable."
            ROBOT_IP="$ip"
            break 2
          else
            echo "$iface ($ip) not reachable, trying next..."
          fi
        fi
      done
    done <<< "$ROBOT_IPS"

    if [[ -z "$ROBOT_IP" ]]; then
      echo "Failed to find a reachable IP for robot $ROBOT_NUMBER"
      exit 1
    fi

    echo "Copying certs from robot..."
    if [[ -n "$PASSWORD" ]]; then
	run sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		"cartken@$ROBOT_IP:$REMOTE_PATH/robot.crt" "$LOCAL_DEST/"
	run sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		"cartken@$ROBOT_IP:$REMOTE_PATH/robot.key" "$LOCAL_DEST/"
    else
      run scp "cartken@$ROBOT_IP:$REMOTE_PATH/robot.crt" "$LOCAL_DEST/"
      run scp "cartken@$ROBOT_IP:$REMOTE_PATH/robot.key" "$LOCAL_DEST/"
    fi
  fi

  # --- Optionally refresh cartken packages from gitlab BEFORE the chroot ---
  # The rootfs already has /root/packages/ baked in by setup_tegra_package.sh,
  # but that snapshot is whatever tag was passed at that time (default: latest).
  # When --tag is given, re-pull the named release and overwrite the rootfs's
  # copy so the chroot's `dpkg -i` lines (notably cartken-jetson-sshd-v2.deb)
  # come from the right tag. Lets you re-flash an existing rootfs at a newer
  # tag without re-running setup_tegra_package.sh end to end.
  #
  # Done before SSH CA provisioning so a missing/incomplete tag aborts before
  # we burn a backend host-cert request.
  if [[ -n "$TAG" && "$REFRESH_SSH_CA_ONLY" -eq 0 ]]; then
    GET_PACKAGES_SH="$SCRIPT_DIRECTORY/helpers/get_packages.sh"
    if [[ ! -x "$GET_PACKAGES_SH" ]]; then
      echo "Error: $GET_PACKAGES_SH not found or not executable." >&2
      exit 1
    fi
    echo "Refreshing cartken packages at tag '$TAG' into $L4T_DIR/packages/..."
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[dry-run] (cd $L4T_DIR && $GET_PACKAGES_SH --access-token <redacted> --tag $TAG)"
      echo "[dry-run] verify $L4T_DIR/packages/cartken-jetson-debians/cartken-jetson-sshd-v2*.deb exists"
      echo "[dry-run] rm -rf $ROOTFS_PATH/root/packages"
      echo "[dry-run] cp -r $L4T_DIR/packages $ROOTFS_PATH/root/"
    else
      (cd "$L4T_DIR" && "$GET_PACKAGES_SH" --access-token "$ACCESS_TOKEN" --tag "$TAG")

      # The whole point of routing through --tag (vs trusting whatever was
      # already in /root/packages) is to guarantee v2 SSH support, so abort
      # loudly if the tag is missing the v2 deb instead of silently flashing
      # a robot that won't have cartken-sshd.
      NEW_DEBS_DIR="$L4T_DIR/packages/cartken-jetson-debians"
      if ! ls "$NEW_DEBS_DIR"/cartken-jetson-sshd-v2*.deb >/dev/null 2>&1; then
        echo "Error: tag '$TAG' did not include cartken-jetson-sshd-v2*.deb in" >&2
        echo "  $NEW_DEBS_DIR" >&2
        echo "Aborting: this tag would flash a robot without v2 SSH support." >&2
        exit 1
      fi

      echo "Replacing $ROOTFS_PATH/root/packages with the freshly-pulled copy."
      rm -rf "$ROOTFS_PATH/root/packages"
      cp -r "$L4T_DIR/packages" "$ROOTFS_PATH/root/"
    fi
  fi

  # --- Provision SSH CA material BEFORE the chroot ---
  # The chroot installs cartken-jetson-sshd-v2.deb; its postinst will land on
  # /etc/ssh/cartken_sshd/ and the unit will start on first boot. Bake the
  # files first so the daemon comes up working, without an AWX round-trip.
  if [[ "$SKIP_SSH_CA" -eq 1 ]]; then
    echo "--skip-ssh-ca set; not provisioning /etc/ssh/cartken_sshd/."
    echo "WARNING: cartken-jetson-sshd-v2 will still be installed in the rootfs"
    echo "and cartken-sshd will fail to start on first boot until AWX"
    echo "update-jetson writes the missing files."
  else
    # Mirrors common/robot-sshd-config-update from it-management. cartken-dev
    # signs the host key and fetches the user CA via the operator's session.
    if [[ -z "${SUDO_USER:-}" ]]; then
      echo "Error: SUDO_USER is unset; cannot run cartken under a non-root user." >&2
      echo "Re-run via 'sudo $0 ...' from a normal user shell that has run" >&2
      echo "  cartken account login $BACKEND_ENV" >&2
      exit 1
    fi

    USER_CA_HELPER="$SCRIPT_DIRECTORY/helpers/fetch_user_ca_pubkey.py"
    if [[ ! -f "$USER_CA_HELPER" ]]; then
      echo "Error: helper '$USER_CA_HELPER' is missing." >&2
      exit 1
    fi

    CARTKEN_BIN="$(resolve_cartken_bin || true)"
    if [[ -z "$CARTKEN_BIN" ]]; then
      echo "Error: 'cartken' could not be found for user '$SUDO_USER'." >&2
      echo "Looked in: ~$SUDO_USER/.local/bin, login PATH, /usr/local/bin, /usr/bin." >&2
      echo "Install cartken-dev and run 'cartken account login $BACKEND_ENV'," >&2
      echo "or re-run this script with --skip-ssh-ca to defer SSH CA setup to AWX." >&2
      exit 1
    fi
    echo "Using cartken at: $CARTKEN_BIN"

    CARTKEN_SSHD_DIR="$ROOTFS_PATH/etc/ssh/cartken_sshd"
    HOST_KEY_PATH="$CARTKEN_SSHD_DIR/ssh_host_cartken_ed25519_key"
    HOST_PUB_PATH="${HOST_KEY_PATH}.pub"
    HOST_CERT_PATH="${HOST_KEY_PATH}-cert.pub"
    USER_CA_PATH="$CARTKEN_SSHD_DIR/ssh_user_ca.pub"
    PRINCIPALS_PATH="$CARTKEN_SSHD_DIR/authorized_principals"
    PRINCIPALS_LOCAL_PATH="$CARTKEN_SSHD_DIR/authorized_principals_local"

    echo "Provisioning $CARTKEN_SSHD_DIR for cart$ROBOT_NUMBER (env=$BACKEND_ENV)..."

    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[dry-run] mkdir -p $CARTKEN_SSHD_DIR && chmod 0755 $CARTKEN_SSHD_DIR"
      echo "[dry-run] rm -f $HOST_KEY_PATH $HOST_PUB_PATH $HOST_CERT_PATH"
      echo "[dry-run] ssh-keygen -t ed25519 -N '' -f $HOST_KEY_PATH -C cart$ROBOT_NUMBER"
      echo "[dry-run] sudo -u $SUDO_USER mktemp -d -t cartken_host_cert.XXXXXX  (then \$BASE/out as --output)"
      echo "[dry-run] sudo -u $SUDO_USER $CARTKEN_BIN robot ssh-cert $ROBOT_NUMBER host -k $HOST_PUB_PATH -o <tmp>/out --env $BACKEND_ENV --validity-duration $HOST_CERT_VALIDITY"
      echo "[dry-run] mv <tmp>/out/cert-0.pub $HOST_CERT_PATH"
      echo "[dry-run] sudo -u $SUDO_USER mktemp -t cartken_user_ca.XXXXXX (then --output that path)"
      echo "[dry-run] sudo -u $SUDO_USER python3 $USER_CA_HELPER --env $BACKEND_ENV --output <tmp>"
      echo "[dry-run] mv <tmp> $USER_CA_PATH"
      echo "[dry-run] write $PRINCIPALS_PATH and $PRINCIPALS_LOCAL_PATH"
    else
      mkdir -p "$CARTKEN_SSHD_DIR"
      chmod 0755 "$CARTKEN_SSHD_DIR"

      # Always regenerate: the rootfs may have been reconfigured for a different
      # robot, in which case any pre-existing key is stale and would not match
      # the cert we are about to sign. Remove host key + pub + any old cert
      # before keygen so ssh-keygen does not prompt to overwrite.
      rm -f "$HOST_KEY_PATH" "$HOST_PUB_PATH" "$HOST_CERT_PATH"
      ssh-keygen -t ed25519 -N "" -f "$HOST_KEY_PATH" -C "cart$ROBOT_NUMBER"
      chmod 0600 "$HOST_KEY_PATH"
      chmod 0644 "$HOST_PUB_PATH"

      # Short validity is intentional: AWX's common/robot-sshd-config-update
      # re-signs the host cert on its first connect, so this only needs to
      # cover the gap between flashing and the first AWX run plus a buffer.
      #
      # `cartken robot ssh-cert host -o <dir>` writes cert-N.pub files into
      # <dir>; <dir> must NOT pre-exist. For host certs there is always
      # exactly one cert (cert-0.pub). User certs may have multiple during
      # CA rotation.
      HOST_CERT_TMP_BASE="$(sudo -u "$SUDO_USER" mktemp -d -t cartken_host_cert.XXXXXX)"
      HOST_CERT_TMP_DIR="$HOST_CERT_TMP_BASE/out"

      echo "Signing host certificate (validity=$HOST_CERT_VALIDITY) via 'cartken robot ssh-cert ... host'..."
      # -H so cartken's Python sees the right HOME for user-site packages
      # (avoids ModuleNotFoundError: cartken_dev when run from sudo'd script).
      sudo -u "$SUDO_USER" -H -E -- "$CARTKEN_BIN" robot ssh-cert "$ROBOT_NUMBER" host \
        --public-key "$HOST_PUB_PATH" \
        --output "$HOST_CERT_TMP_DIR" \
        --validity-duration "$HOST_CERT_VALIDITY" \
        --env "$BACKEND_ENV"

      if [[ ! -f "$HOST_CERT_TMP_DIR/cert-0.pub" ]]; then
        echo "Error: cartken did not produce $HOST_CERT_TMP_DIR/cert-0.pub" >&2
        ls -la "$HOST_CERT_TMP_DIR" >&2 || true
        rm -rf "$HOST_CERT_TMP_BASE"
        exit 1
      fi
      mv "$HOST_CERT_TMP_DIR/cert-0.pub" "$HOST_CERT_PATH"
      chmod 0644 "$HOST_CERT_PATH"
      rm -rf "$HOST_CERT_TMP_BASE"

      echo "Fetching user CA public key(s) via fetch_user_ca_pubkey.py..."
      # The helper runs as $SUDO_USER (it uses the user's cartken-dev session),
      # so it can't write directly into the root-owned rootfs. Write to a
      # user-owned tmp file first, then mv into place as root. Same pattern as
      # the host-cert step above. -H so cartken_dev imports cleanly.
      USER_CA_TMP="$(sudo -u "$SUDO_USER" mktemp -t cartken_user_ca.XXXXXX)"
      sudo -u "$SUDO_USER" -H -E -- python3 "$USER_CA_HELPER" \
        --env "$BACKEND_ENV" \
        --output "$USER_CA_TMP"
      mv "$USER_CA_TMP" "$USER_CA_PATH"
      chmod 0644 "$USER_CA_PATH"

      # Mirror common/robot-sshd-config-update on it-management
      # (awx_ssh_ca_integration_2): authorized_principals = cart<N> + admin;
      # authorized_principals_local additionally allows cart<N>-local and
      # admin-local for hotspot / inter-board connections.
      printf 'cart%s\nadmin\n' "$ROBOT_NUMBER" > "$PRINCIPALS_PATH"
      chmod 0644 "$PRINCIPALS_PATH"
      printf 'cart%s\ncart%s-local\nadmin\nadmin-local\n' \
        "$ROBOT_NUMBER" "$ROBOT_NUMBER" > "$PRINCIPALS_LOCAL_PATH"
      chmod 0644 "$PRINCIPALS_LOCAL_PATH"

      chown -R 0:0 "$CARTKEN_SSHD_DIR"
      echo "Provisioned $CARTKEN_SSHD_DIR for cart$ROBOT_NUMBER."
    fi
  fi

  if [[ "$REFRESH_SSH_CA_ONLY" -eq 1 ]]; then
    echo "--refresh-ssh-ca-only complete: refreshed /etc/ssh/cartken_sshd/ in rootfs."
    exit 0
  fi

  echo "Running chroot (installs cartken-jetson-sshd-v2 among others)..."
  CARTKEN_DEBS_MANIFEST="$SCRIPT_DIRECTORY/cartken_jetson_debs.txt"
  if [[ ! -f "$CARTKEN_DEBS_MANIFEST" ]]; then
    echo "Error: cartken package manifest '$CARTKEN_DEBS_MANIFEST' is missing." >&2
    exit 1
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] cp $CARTKEN_DEBS_MANIFEST $ROOTFS_PATH/root/cartken_jetson_debs.txt"
  else
    cp "$CARTKEN_DEBS_MANIFEST" "$ROOTFS_PATH/root/cartken_jetson_debs.txt"
  fi
  if [[ ! -s "$CHROOT_CMD_FILE" ]]; then
    echo "Error: chroot command file '$CHROOT_CMD_FILE' is missing or empty." >&2
    echo "Refusing to run chroot with no commands; this would silently leave" >&2
    echo "cartken-jetson-sshd-v2 (and others) uninstalled." >&2
    exit 1
  fi
  JETSON_CHROOT_SH="$L4T_DIR/jetson_chroot.sh"
  if [[ ! -x "$JETSON_CHROOT_SH" ]]; then
    JETSON_CHROOT_SH="$SCRIPT_DIRECTORY/jetson_chroot.sh"
  fi
  if [[ ! -x "$JETSON_CHROOT_SH" ]]; then
    echo "Error: jetson_chroot.sh not found under $L4T_DIR or $SCRIPT_DIRECTORY." >&2
    exit 1
  fi
  run sudo "$JETSON_CHROOT_SH" "$ROOTFS_PATH" "$SOC" "$CHROOT_CMD_FILE"

  # --- Set hostname and env ---
  NEW_HOSTNAME="cart${ROBOT_NUMBER}jetson"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] echo $NEW_HOSTNAME > $ROOTFS_PATH/etc/hostname"
    echo "[dry-run] update 127.0.1.1 line in $ROOTFS_PATH/etc/hosts to $NEW_HOSTNAME"
    echo "[dry-run] set CARTKEN_CART_NUMBER=$ROBOT_NUMBER in $ROOTFS_PATH/etc/environment"
  else
    echo "Setting hostname to $NEW_HOSTNAME in $ROOTFS_PATH/etc/hostname"
    echo "$NEW_HOSTNAME" > "$ROOTFS_PATH/etc/hostname"

    echo "Updating /etc/hosts to reflect new hostname"
    if grep -q "^127\.0\.1\.1" "$ROOTFS_PATH/etc/hosts"; then
      sed -i "s/^127\.0\.1\.1.*/127.0.1.1    $NEW_HOSTNAME/" "$ROOTFS_PATH/etc/hosts"
    else
      echo "127.0.1.1    $NEW_HOSTNAME" >> "$ROOTFS_PATH/etc/hosts"
    fi

    echo "Writing CARTKEN_CART_NUMBER=$ROBOT_NUMBER to /etc/environment"
    if grep -q "^CARTKEN_CART_NUMBER=" "$ROOTFS_PATH/etc/environment"; then
      sed -i "s/^CARTKEN_CART_NUMBER=.*/CARTKEN_CART_NUMBER=$ROBOT_NUMBER/" "$ROOTFS_PATH/etc/environment"
    else
      echo "CARTKEN_CART_NUMBER=$ROBOT_NUMBER" >> "$ROOTFS_PATH/etc/environment"
    fi
  fi
fi

read -rp "✅ Rootfs at $L4T_DIR is ready for flashing. Please put the robot in recovery mode and press [Enter] to continue..."

if [ -f "$L4T_DIR/tools/l4t_flash_prerequisites.sh" ]; then
  echo "Running l4t_flash_prerequisites.sh..."
  (cd "$L4T_DIR" && ./tools/l4t_flash_prerequisites.sh)
fi

# --- Flash ---
# Stage the flash script from the local checkout rather than pulling it
# from GitHub master. Same reasoning as setup_tegra_package.sh's local-cp
# refactor: works offline, doesn't silently overwrite feature-branch
# edits, no curl/network failure mode mid-flash.
FLASH_SCRIPT_SRC="$SCRIPT_DIRECTORY/flash_jetson_ALL_sdmmc_partition_qspi.sh"
if [[ ! -f "$FLASH_SCRIPT_SRC" ]]; then
  echo "Error: $FLASH_SCRIPT_SRC not found." >&2
  exit 1
fi
echo "Staging flash script $FLASH_SCRIPT_SRC -> $FLASH_SCRIPT"
cp "$FLASH_SCRIPT_SRC" "$FLASH_SCRIPT"
chmod +x "$FLASH_SCRIPT"

MAJOR_VERSION=$(echo "$TARGET_BSP" | cut -d. -f1)

if [[ "$MAJOR_VERSION" -ge 6 ]]; then
  DTB_FILE="$L4T_DIR/kernel/dtb/tegra234-p3737-0000+p3701-0000.dtb"
  echo "Jetpack 6.0+ detected, using DTB file: $DTB_FILE"
  sudo "$FLASH_SCRIPT" --l4t-dir "$L4T_DIR" --dtb-file "$DTB_FILE"
else
  sudo "$FLASH_SCRIPT" --l4t-dir "$L4T_DIR"
fi
