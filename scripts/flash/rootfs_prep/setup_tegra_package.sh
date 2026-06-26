#!/bin/bash

set -e
# Command tracing (`set -x`) is extremely noisy — it echoes every line of the
# script, which even turns `--help` into a wall of `+ ...` output. Keep it
# opt-in for troubleshooting: run with SETUP_DEBUG=1 to enable.
[[ -n "${SETUP_DEBUG:-}" ]] && set -x

# --- Optional Docker wrapper ----------------------------------------------
# If --docker is given, re-launch this script inside a consistent
# Ubuntu container that has all the host build-deps preinstalled
# (qemu-user-static, build-essential, kmod, flex, bison, libelf-dev, ...).
# Same pattern as setup_rootfs_as_robot_for_flashing.sh's --docker mode.
#
# This replaces the old separate setup_tegra_package_docker.sh wrapper:
# one entry point, one set of flags, no risk of the two drifting.
#
# Wrapper-only flags (consumed here, NOT passed into the container):
#   --docker     -> enable Docker mode
#   --inspect    -> drop into /bin/bash instead of running the script
#   --rebuild    -> force-rebuild the jetson_builder:latest image
#
# Pre-scan args before the main parse loop runs so we can act on the
# wrapper-only flags first.
DOCKER_FLAG_PRESENT=0
INSPECT=0
REBUILD=0
WRAPPER_JETPACK=""
ARGS=("$@")
idx=0
	while [[ $idx -lt ${#ARGS[@]} ]]; do
	arg="${ARGS[$idx]}"
	case "$arg" in
		--docker)  DOCKER_FLAG_PRESENT=1 ;;
		--inspect) INSPECT=1 ;;
		--rebuild) REBUILD=1 ;;
		-j|--jetpack)
			if [[ $((idx + 1)) -lt ${#ARGS[@]} ]]; then
				WRAPPER_JETPACK="${ARGS[$((idx + 1))]}"
				idx=$((idx + 1))
			fi
			;;
		--jetpack=*)
			WRAPPER_JETPACK="${arg#*=}"
			;;
	esac
	idx=$((idx + 1))
done

if [[ "$DOCKER_FLAG_PRESENT" -eq 1 ]]; then
	if [[ "$EUID" -ne 0 ]]; then
		echo "This script must be run with sudo when using --docker." >&2
		exit 1
	fi

	# Quiet down `set -x` for the wrapper itself; it's noisy and the
	# wrapper steps are self-documenting via their echo'd messages.
	set +x

	resolve_docker_bin() {
		local candidate=""
		for candidate in "${DOCKER_BIN:-}" docker /usr/bin/docker /usr/local/bin/docker /bin/docker; do
			[[ -n "$candidate" ]] || continue
			if command -v "$candidate" >/dev/null 2>&1; then
				command -v "$candidate"
				return 0
			fi
			if [[ -x "$candidate" ]]; then
				echo "$candidate"
				return 0
			fi
		done
		return 1
	}

	DOCKER_BIN="$(resolve_docker_bin || true)"
	if [[ -z "$DOCKER_BIN" ]]; then
		echo "Error: docker binary not found in PATH under sudo." >&2
		echo "       PATH=$PATH" >&2
		echo "       Checked: docker, /usr/bin/docker, /usr/local/bin/docker, /bin/docker" >&2
		exit 1
	fi

	SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
	WRAPPER_JP_MAJOR="${WRAPPER_JETPACK%%.*}"
	if [[ "$WRAPPER_JP_MAJOR" == "7"* ]]; then
		IMAGE="ubuntu:24.04"
		DOCKER_TAG="jetson_builder:jp7-ubuntu2404"
	else
		IMAGE="ubuntu:22.04"
		DOCKER_TAG="jetson_builder:jp56-ubuntu2204"
	fi
	CONTAINER_NAME="tegra_setup"

	echo "Docker base image selected from --jetpack '${WRAPPER_JETPACK:-default}': $IMAGE"

	echo "Checking host dependencies for cross-architecture container support..."
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
		fi
	elif [[ "$OS" == "Arch Linux" || "$OS" == "Manjaro Linux" || "$OS" == "EndeavourOS" ]]; then
		if ! pacman -Q | grep -q "qemu-user-static" || ! pacman -Q | grep -q "binfmt-support"; then
			echo "Installing QEMU and binfmt support for Arch Linux..."
			pacman -Syu --noconfirm qemu-user-static qemu-user-static-binfmt
		fi
	else
		echo "Unsupported operating system for automatic dependency installation: $OS" >&2
		exit 1
	fi

	echo "Registering QEMU handlers with the kernel for ARM64 emulation..."
	"$DOCKER_BIN" run --rm --privileged multiarch/qemu-user-static --reset -p yes > /dev/null

	if [[ "$REBUILD" -eq 1 || "$("$DOCKER_BIN" images -q "$DOCKER_TAG" 2>/dev/null)" == "" ]]; then
		echo "Building Docker image '$DOCKER_TAG'..."
		"$DOCKER_BIN" pull "$IMAGE"
		if [[ "$WRAPPER_JP_MAJOR" == "7"* ]]; then
			"$DOCKER_BIN" build -t "$DOCKER_TAG" - <<EOF
FROM $IMAGE
RUN apt-get update && apt-get install -y \
	sudo tar bzip2 git wget curl openssh-client iputils-ping \
	docker.io jq qemu-user-static binfmt-support unzip \
	build-essential kmod flex bison libelf-dev bc dwarves \
	ccache libncurses5-dev vim-common rsync zlib1g libssl-dev \
	device-tree-compiler \
	&& mkdir -p /opt/nvidia-l4t-toolchain \
	&& wget -q -O /tmp/x-tools.tbz2 https://developer.download.nvidia.com/embedded/L4T/r38_Release_v2.0/release/x-tools.tbz2 \
	&& tar -xjf /tmp/x-tools.tbz2 -C /opt/nvidia-l4t-toolchain \
	&& rm -f /tmp/x-tools.tbz2 \
	&& test -x /opt/nvidia-l4t-toolchain/x-tools/aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-gcc
EOF
		else
			"$DOCKER_BIN" build -t "$DOCKER_TAG" - <<EOF
FROM $IMAGE
RUN apt-get update && apt-get install -y \
	sudo tar bzip2 git wget curl openssh-client iputils-ping \
	docker.io jq qemu-user-static binfmt-support unzip \
	build-essential kmod flex bison libelf-dev bc dwarves \
	ccache libncurses5-dev vim-common rsync zlib1g libssl-dev device-tree-compiler
EOF
		fi
	else
		echo "Using existing Docker image: $DOCKER_TAG"
	fi

	# Stop any previous run that crashed and left a container behind.
	if "$DOCKER_BIN" ps -a --format '{{.Names}}' | grep -qw "$CONTAINER_NAME"; then
		echo "Removing existing container: $CONTAINER_NAME"
		"$DOCKER_BIN" rm -f "$CONTAINER_NAME"
	fi

	# Forward every arg except the wrapper-only flags. printf %q quotes
	# values that contain spaces / special chars correctly.
	INNER_ARGS=()
	for arg in "$@"; do
		case "$arg" in
			--docker|--inspect|--rebuild) ;;
			*) INNER_ARGS+=("$(printf '%q' "$arg")") ;;
		esac
	done

	if [[ "$INSPECT" -eq 1 ]]; then
		CONTAINER_CMD="/bin/bash"
	else
		CONTAINER_CMD="./$(basename "${BASH_SOURCE[0]}") ${INNER_ARGS[*]}"
	fi

	# -it for --inspect (interactive shell), -i otherwise (so that this
	# can be invoked from non-interactive contexts like CI / OTA build
	# scripts without a controlling tty).
	if [[ "$INSPECT" -eq 1 ]]; then
		DOCKER_INTERACTIVE_FLAGS=("-it")
	else
		DOCKER_INTERACTIVE_FLAGS=("-i")
	fi

	echo "Re-launching inside Docker (image=$DOCKER_TAG, container=$CONTAINER_NAME)."
	echo "All subsequent output is from the container."
	"$DOCKER_BIN" run --rm "${DOCKER_INTERACTIVE_FLAGS[@]}" \
		--name "$CONTAINER_NAME" \
		--privileged \
		--network=host \
		-v "$SCRIPT_DIR:/workspace" \
		-v "/var/run/docker.sock:/var/run/docker.sock" \
		-w "/workspace" \
		-e HOME="/workspace" \
		-e SUDO_USER="${SUDO_USER-}" \
		-e KB_IN_DOCKER_WRAPPER="1" \
		"$DOCKER_TAG" \
		/bin/bash -c "$CONTAINER_CMD"

	exit $?
fi
# --- End Docker wrapper ---------------------------------------------------

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

# --- Helper Functions ---
PROMPT=false
prompt_user() {
    if [ "$PROMPT" = true ]; then
        echo "------------------------------------------------------"
        echo "Script paused. Press Enter to continue..."
        read -r
        echo "------------------------------------------------------"
    fi
}

resolve_cartken_manifest_for_packages() {
	local src_manifest="$1"
	local package_dir="$2"
	local out_manifest="$3"
	local line pkg chosen alt optional_missing
	local -a missing=()
	declare -A seen=()

	if [[ ! -f "$src_manifest" ]]; then
		echo "Error: cartken manifest not found: $src_manifest" >&2
		return 1
	fi
	if [[ ! -d "$package_dir" ]]; then
		echo "Error: package directory not found: $package_dir" >&2
		return 1
	fi

	: > "$out_manifest"
	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ "$line" =~ ^[[:space:]]*# ]] && continue
		pkg="${line%%#*}"
		pkg="${pkg// /}"
		[[ -z "$pkg" ]] && continue

		chosen="$pkg"
		optional_missing=0
		if [[ ! -f "$package_dir/$chosen.deb" ]]; then
			alt=""
			case "$pkg" in
				cartken-jetson-sshd-v2) alt="cartken-jetson-sshd" ;;
				cartken-jetson-sshd) alt="cartken-jetson-sshd-v2" ;;
				cartken-jetson-sshd-disable) optional_missing=1 ;;
			esac
			if [[ -n "$alt" && -f "$package_dir/$alt.deb" ]]; then
				echo "Info: using fallback package '$alt' for '$pkg'." >&2
				chosen="$alt"
			elif [[ "$optional_missing" -eq 1 ]]; then
				echo "Info: optional package '$pkg' not present; skipping." >&2
				continue
			else
				missing+=("$pkg")
				continue
			fi
		fi

		if [[ -z "${seen[$chosen]:-}" ]]; then
			echo "$chosen" >> "$out_manifest"
			seen["$chosen"]=1
		fi
	done < "$src_manifest"

	if [[ ${#missing[@]} -gt 0 ]]; then
		echo "Error: missing required Cartken debs after get_packages.sh:" >&2
		printf '  - %s\n' "${missing[@]}" >&2
		echo "Checked under: $package_dir" >&2
		return 1
	fi

	if [[ ! -s "$out_manifest" ]]; then
		echo "Error: resolved Cartken manifest is empty: $out_manifest" >&2
		return 1
	fi

	return 0
}

# Define JetPack versions and corresponding L4T versions
declare -A JETPACK_L4T_MAP=(
    [5.1.2]=35.4.1
    [5.1.3]=35.5.0
	[5.1.4]=35.6.0
	[5.1.5]=35.6.1
	[6.0DP]=36.2
	[6.1]=36.4
	[6.2]=36.4.3
	[7.2]=39.2.0
)

# Define URLs for the sources
declare -A ROOTFS_URLS=(
    [5.1.2]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/release/tegra_linux_sample-root-filesystem_r35.4.1_aarch64.tbz2"
    [5.1.3]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/release/tegra_linux_sample-root-filesystem_r35.5.0_aarch64.tbz2"
	[5.1.4]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.0/release/tegra_linux_sample-root-filesystem_r35.6.0_aarch64.tbz2"
	[5.1.5]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.1/tegra_linux_sample-root-filesystem_r35.6.1_aarch64.tbz2"
	[6.0DP]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v2.0/release/tegra_linux_sample-root-filesystem_r36.2.0_aarch64.tbz2"
	[6.1]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.0/release/Tegra_Linux_Sample-Root-Filesystem_R36.4.0_aarch64.tbz2"
	[6.2]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/release/Tegra_Linux_Sample-Root-Filesystem_r36.4.3_aarch64.tbz2"
	[7.2]="https://developer.nvidia.com/downloads/embedded/L4T/r39_Release_v2.0/release/Tegra_Linux_Sample-Root-Filesystem_R39.2.0_aarch64.tbz2"
)

declare -A KERNEL_URLS=(
    [5.1.2]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/sources/public_sources.tbz2"
    [5.1.3]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/sources/public_sources.tbz2"
	[5.1.4]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.0/sources/public_sources.tbz2"
	[5.1.5]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.1/sources/public_sources.tbz2"
	[6.0DP]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v2.0/sources/public_sources.tbz2"
	[6.1]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.0/sources/public_sources.tbz2"
	[6.2]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/sources/public_sources.tbz2"
	[7.2]="https://developer.nvidia.com/downloads/embedded/L4T/r39_Release_v2.0/sources/public_sources.tbz2"
)

declare -A DRIVER_URLS=(
    [5.1.2]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/release/jetson_linux_r35.4.1_aarch64.tbz2"
    [5.1.3]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/release/jetson_linux_r35.5.0_aarch64.tbz2"
	[5.1.4]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.0/release/jetson_linux_r35.6.0_aarch64.tbz2"
	[5.1.5]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.1/release/jetson_linux_r35.6.1_aarch64.tbz2"
	[6.0DP]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v2.0/release/jetson_linux_r36.2.0_aarch64.tbz2"
	[6.1]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.0/release/Jetson_Linux_R36.4.0_aarch64.tbz2"
	[6.2]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/release/Jetson_Linux_r36.4.3_aarch64.tbz2"
	[7.2]="https://developer.nvidia.com/downloads/embedded/L4T/r39_Release_v2.0/release/Jetson_Linux_R39.2.0_aarch64.tbz2"
)

# Default values
JETPACK_VERSION="5.1.3"
DOWNLOAD=true
ACCESS_TOKEN=""
TAG="latest"
SOC="orin"
SKIP_KERNEL_BUILD=false
SKIP_DISPLAY_DRIVER_BUILD=false
SKIP_CHROOT_BUILD=false
SKIP_PINMUX=false
SKIP_PREP=false
ONLY_CARTKEN_CHROOT=false
ONLY_KERNEL_BUILD=false
ONLY_OOT_MODULES_BUILD=false
ONLY_INSTALL_KERNEL_ARTIFACTS=false
SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=helpers/ensure_jp7_kernel_src.sh
source "$SCRIPT_DIRECTORY/helpers/ensure_jp7_kernel_src.sh"

# Function to show help
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -j, --jetpack VERSION   Specify JetPack version (default: $JETPACK_VERSION)"
	echo "  --access-token TOKEN    Provide the access token (required)"
    echo "  --tag TAG               Specify tag for get_packages.sh (default: $TAG)"
    echo "  --soc SOC               Specify SoC type for jetson_chroot.sh (default: $SOC)"
	echo "  --skip-kernel-build		Skips building the kernel"
	echo "  --skip-display-driver-build		Skips building the display driver"
	echo "  --skip-chroot-build		Skips updating and settup up the rootfs in a chroot"
	echo "  --skip-pinmux		    Skips overriding the pinmux"
	echo "  --skip-prep                     Reuse existing BSP/rootfs and skip download/extract/apply_binaries/default-user setup"
	echo "  --only-cartken-chroot          Fast loop: run only cartken chroot pass on existing BSP/rootfs"
	echo "  --only-kernel-build            Fast loop: build/install kernel on existing BSP/rootfs only"
	echo "  --only-oot-modules-build       Fast loop: build/install NVIDIA OOT/display modules only (reuse kernel_out)"
	echo "  --only-install-kernel-artifacts Fast loop: copy existing kernel Image/DTB from kernel_out only"
    echo "  --no-download           Use existing .tbz2 files instead of downloading"
	echo "  --just-clone		    Only pulls the sources, nothing more"
    echo "  --prompt                Prompt user to press Enter at each major step"
    echo "  --docker                Re-launch inside a pre-configured container"
    echo "                          (JP5/6 -> ubuntu:22.04, JP7 -> ubuntu:24.04)."
    echo "                          All subsequent options are forwarded into the container."
    echo "  --inspect               (with --docker) Drop into /bin/bash inside the container"
    echo "                          instead of running the script. Useful for debugging."
    echo "  --rebuild               (with --docker) Force-rebuild the jetson_builder image"
    echo "                          (e.g. after editing the Dockerfile in this script)."
    echo "  -h, --help              Show this help message"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -j|--jetpack)
            JETPACK_VERSION="$2"
            shift 2
            ;;
        --access-token)
            ACCESS_TOKEN="$2"
            shift 2
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        --soc)
            SOC="$2"
            shift 2
            ;;
        --no-download)
            DOWNLOAD=false
            shift
            ;;
		--just-clone)
			JUST_CLONE=true
			shift
			;;
        --skip-kernel-build)
            SKIP_KERNEL_BUILD=true
            shift
            ;;
        --skip-display-driver-build)
            SKIP_DISPLAY_DRIVER_BUILD=true
            shift
            ;;
        --skip-chroot-build)
            SKIP_CHROOT_BUILD=true
            shift
            ;;
        --skip-pinmux)
            SKIP_PINMUX=true
            shift
            ;;
        --skip-prep)
            SKIP_PREP=true
            shift
            ;;
        --only-cartken-chroot)
            ONLY_CARTKEN_CHROOT=true
            shift
            ;;
        --only-kernel-build)
            ONLY_KERNEL_BUILD=true
            shift
            ;;
        --only-oot-modules-build)
            ONLY_OOT_MODULES_BUILD=true
            shift
            ;;
        --only-install-kernel-artifacts)
            ONLY_INSTALL_KERNEL_ARTIFACTS=true
            shift
            ;;
        --prompt)
            PROMPT=true
            shift
            ;;
        --inspect|--rebuild)
            echo "Error: $1 only applies together with --docker." >&2
            echo "       See $0 --help." >&2
            exit 1
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

if [[ -z "${JETPACK_L4T_MAP[$JETPACK_VERSION]}" ]]; then
	echo "Error: Unsupported JetPack version. Use --help to see available versions."
	exit 1
fi

if [[ "$ONLY_CARTKEN_CHROOT" == true ]]; then
	SKIP_PREP=true
	SKIP_CHROOT_BUILD=true
	SKIP_PINMUX=true
	SKIP_KERNEL_BUILD=true
	SKIP_DISPLAY_DRIVER_BUILD=true
fi

if [[ "$ONLY_KERNEL_BUILD" == true ]]; then
	SKIP_PREP=true
	SKIP_CHROOT_BUILD=true
	SKIP_PINMUX=true
	SKIP_DISPLAY_DRIVER_BUILD=true
fi

if [[ "$ONLY_OOT_MODULES_BUILD" == true ]]; then
	SKIP_PREP=true
	SKIP_CHROOT_BUILD=true
	SKIP_PINMUX=true
	SKIP_DISPLAY_DRIVER_BUILD=true
fi

if [[ "$ONLY_INSTALL_KERNEL_ARTIFACTS" == true ]]; then
	SKIP_PREP=true
	SKIP_CHROOT_BUILD=true
	SKIP_PINMUX=true
	SKIP_KERNEL_BUILD=true
	SKIP_DISPLAY_DRIVER_BUILD=true
fi

if [[ "$ONLY_CARTKEN_CHROOT" == false && "$ONLY_KERNEL_BUILD" == false && "$ONLY_OOT_MODULES_BUILD" == false && "$ONLY_INSTALL_KERNEL_ARTIFACTS" == false && -z "$ACCESS_TOKEN" ]]; then
	echo "Error: --access-token is required."
	exit 1
fi

if [[ "$JETPACK_VERSION" == 7.* && "$DOCKER_FLAG_PRESENT" -ne 1 && "${KB_IN_DOCKER_WRAPPER:-0}" != "1" ]]; then
	echo "Error: JetPack $JETPACK_VERSION must be run with --docker on non-Ubuntu hosts." >&2
	echo "Use: $0 --docker --jetpack $JETPACK_VERSION [other options]" >&2
	exit 1
fi

# Multi-GB BSP / kernel-source / rootfs tarballs go into a dedicated
# downloads/ subdir so they don't clutter the rootfs_prep/ root. Migrate
# any legacy downloads sitting at the old location (rootfs_prep/*.tbz2 or
# rootfs_prep/*.tar.gz) into downloads/ so re-runs don't waste bandwidth
# re-fetching them.
DOWNLOADS_DIR="$SCRIPT_DIRECTORY/downloads"
mkdir -p "$DOWNLOADS_DIR"
shopt -s nullglob
for legacy in "$SCRIPT_DIRECTORY"/*.tbz2 "$SCRIPT_DIRECTORY"/*.tar.gz; do
	[[ -f "$legacy" ]] || continue
	target="$DOWNLOADS_DIR/$(basename "$legacy")"
	if [[ ! -f "$target" ]]; then
		echo "Migrating legacy download $(basename "$legacy") into downloads/..."
		mv "$legacy" "$target"
	fi
done
shopt -u nullglob

ROOTFS_FILE="$DOWNLOADS_DIR/$(basename "${ROOTFS_URLS[$JETPACK_VERSION]}")"
KERNEL_FILE="$DOWNLOADS_DIR/$(basename "${KERNEL_URLS[$JETPACK_VERSION]}")"
DRIVER_FILE="$DOWNLOADS_DIR/$(basename "${DRIVER_URLS[$JETPACK_VERSION]}")"

# Extracted L4T BSPs land in bsp/<jetpack>/Linux_for_Tegra/. The bsp/
# wrapper makes it obvious at a glance what the version-numbered dirs are
# (vs. random "5.1.5/" sitting at the rootfs_prep/ root). Migrate any
# legacy version-named dir from rootfs_prep/ into bsp/ on the fly so
# previous-run BSPs don't get re-downloaded just because they are at the
# old location.
BSP_ROOT="$SCRIPT_DIRECTORY/bsp"
mkdir -p "$BSP_ROOT"
LEGACY_BSP="$SCRIPT_DIRECTORY/$JETPACK_VERSION"
if [[ -d "$LEGACY_BSP" && ! -d "$BSP_ROOT/$JETPACK_VERSION" ]]; then
	echo "Migrating legacy BSP dir $LEGACY_BSP -> $BSP_ROOT/$JETPACK_VERSION..."
	sudo mv "$LEGACY_BSP" "$BSP_ROOT/$JETPACK_VERSION"
fi
TEGRA_BASE_DIR="$BSP_ROOT/$JETPACK_VERSION"
TEGRA_DIR="$TEGRA_BASE_DIR/Linux_for_Tegra"

if [[ "$ONLY_CARTKEN_CHROOT" == true ]]; then
	if [[ ! -d "$TEGRA_DIR/rootfs" ]]; then
		echo "Error: --only-cartken-chroot requires an existing rootfs at $TEGRA_DIR/rootfs" >&2
		echo "Run a full setup once, then use this fast mode for reruns." >&2
		exit 1
	fi

	echo "Fast loop enabled: syncing helper scripts into $TEGRA_DIR and running only cartken chroot pass."
	shopt -s nullglob
	helper_files=(
		"$SCRIPT_DIRECTORY"/*.sh
		"$SCRIPT_DIRECTORY"/*.txt
		"$SCRIPT_DIRECTORY"/helpers/*.sh
		"$SCRIPT_DIRECTORY"/helpers/*.py
	)
	shopt -u nullglob
	if [[ ${#helper_files[@]} -eq 0 ]]; then
		echo "Error: no helper scripts found at $SCRIPT_DIRECTORY" >&2
		exit 1
	fi
	cp "${helper_files[@]}" "$TEGRA_DIR/"
	chmod +x "$TEGRA_DIR/jetson_chroot.sh"

	if [[ "$JETPACK_VERSION" == 7.* ]]; then
		CARTKEN_CHROOT_FILE="chroot_install_cartken_jp7.txt"
	else
		CARTKEN_CHROOT_FILE="chroot_install_cartken.txt"
	fi
	if [[ ! -f "$TEGRA_DIR/$CARTKEN_CHROOT_FILE" ]]; then
		echo "Error: missing $CARTKEN_CHROOT_FILE in $TEGRA_DIR" >&2
		exit 1
	fi

	RESOLVED_CARTKEN_DEBS_HOST="$(mktemp -p "$TEGRA_DIR" cartken_jetson_debs.resolved.XXXXXX.txt)"
	resolve_cartken_manifest_for_packages \
		"$SCRIPT_DIRECTORY/cartken_jetson_debs.txt" \
		"$TEGRA_DIR/packages/cartken-jetson-debians" \
		"$RESOLVED_CARTKEN_DEBS_HOST"
	sudo cp "$RESOLVED_CARTKEN_DEBS_HOST" "$TEGRA_DIR/rootfs/root/cartken_jetson_debs.txt"
	rm -f "$RESOLVED_CARTKEN_DEBS_HOST"

	(
		cd "$TEGRA_DIR"
		sudo ./jetson_chroot.sh rootfs "$SOC" "$CARTKEN_CHROOT_FILE"
	)
	echo "Fast cartken chroot pass completed."
	exit 0
fi

if [[ "$ONLY_KERNEL_BUILD" == true ]]; then
	if [[ ! -d "$TEGRA_DIR/kernel_src" || ! -d "$TEGRA_DIR/rootfs" ]]; then
		echo "Error: --only-kernel-build requires existing kernel_src and rootfs under $TEGRA_DIR" >&2
		exit 1
	fi

	echo "Kernel-only build: syncing helpers and building kernel for JetPack $JETPACK_VERSION..."
	shopt -s nullglob
	helper_files=(
		"$SCRIPT_DIRECTORY"/*.sh
		"$SCRIPT_DIRECTORY"/*.txt
		"$SCRIPT_DIRECTORY"/helpers/*.sh
		"$SCRIPT_DIRECTORY"/helpers/*.py
	)
	shopt -u nullglob
	cp "${helper_files[@]}" "$TEGRA_DIR/"
	find "$TEGRA_DIR" -maxdepth 1 -name '*.sh' -type f -exec chmod +x {} +

	if [[ "$JETPACK_VERSION" != 7.* && ! -d "$TEGRA_DIR/toolchain" ]]; then
		echo "Cloning Jetson Linux toolchain into $TEGRA_DIR/toolchain..."
		sudo git clone --config core.symlinks=true --depth=1 https://github.com/alxhoff/jetson-linux-toolchain "$TEGRA_DIR/toolchain"
	fi

	if [[ "$JETPACK_VERSION" == 7.* ]]; then
		ensure_jp7_kernel_src_complete "$TEGRA_DIR/kernel_src" "$KERNEL_FILE"
	fi

	KERNEL_BUILD_ARGS=(--patch "$JETPACK_VERSION" --localversion "-cartken$JETPACK_VERSION" --skip-patches --public-sources "$KERNEL_FILE")
	if [[ "$JETPACK_VERSION" == 7.* && ! -f "$SCRIPT_DIRECTORY/../../../sources/configs/$JETPACK_VERSION/defconfig" ]]; then
		echo "No sources/configs/$JETPACK_VERSION/defconfig yet; using stock NVIDIA defconfig and skipping third-party drivers."
		KERNEL_BUILD_ARGS+=(--skip-third-party-drivers)
	fi
	if [[ ! -d "$SCRIPT_DIRECTORY/../../../sources/patches/$JETPACK_VERSION" ]]; then
		echo "No local sources/patches/$JETPACK_VERSION yet; skipping kernel patch fetch."
	fi

	(
		cd "$TEGRA_DIR"
		sudo ./build_kernel.sh "${KERNEL_BUILD_ARGS[@]}"
	)
	echo "Kernel-only build completed."
	exit 0
fi

if [[ "$ONLY_OOT_MODULES_BUILD" == true ]]; then
	if [[ "$JETPACK_VERSION" != 6.* && "$JETPACK_VERSION" != 7.* ]]; then
		echo "Error: --only-oot-modules-build is supported for JetPack 6.x and 7.x only." >&2
		exit 1
	fi
	if [[ ! -d "$TEGRA_DIR/kernel_src" || ! -d "$TEGRA_DIR/rootfs" ]]; then
		echo "Error: --only-oot-modules-build requires existing kernel_src and rootfs under $TEGRA_DIR" >&2
		exit 1
	fi
	if [[ ! -d "$TEGRA_DIR/kernel_src/kernel_out/kernel" ]]; then
		echo "Error: --only-oot-modules-build requires an existing kernel_out build under $TEGRA_DIR/kernel_src" >&2
		echo "Run --only-kernel-build first (or a full kernel build)." >&2
		exit 1
	fi

	echo "OOT-only build: syncing helpers and building NVIDIA OOT/display modules for JetPack $JETPACK_VERSION..."
	shopt -s nullglob
	helper_files=(
		"$SCRIPT_DIRECTORY"/*.sh
		"$SCRIPT_DIRECTORY"/*.txt
		"$SCRIPT_DIRECTORY"/helpers/*.sh
		"$SCRIPT_DIRECTORY"/helpers/*.py
	)
	shopt -u nullglob
	cp "${helper_files[@]}" "$TEGRA_DIR/"
	find "$TEGRA_DIR" -maxdepth 1 -name '*.sh' -type f -exec chmod +x {} +

	KERNEL_BUILD_ARGS=(
		--patch "$JETPACK_VERSION"
		--localversion "-cartken$JETPACK_VERSION"
		--skip-patches
		--only-oot-modules
		--skip-third-party-drivers
		--public-sources "$KERNEL_FILE"
	)

	(
		cd "$TEGRA_DIR"
		sudo ./build_kernel.sh "${KERNEL_BUILD_ARGS[@]}"
	)
	echo "OOT-only build completed."
	exit 0
fi

if [[ "$ONLY_INSTALL_KERNEL_ARTIFACTS" == true ]]; then
	if [[ "$JETPACK_VERSION" != 6.* && "$JETPACK_VERSION" != 7.* ]]; then
		echo "Error: --only-install-kernel-artifacts is supported for JetPack 6.x and 7.x only." >&2
		exit 1
	fi
	if [[ ! -d "$TEGRA_DIR/kernel_src/kernel_out/kernel" ]]; then
		echo "Error: --only-install-kernel-artifacts requires kernel_out under $TEGRA_DIR/kernel_src" >&2
		exit 1
	fi

	echo "Kernel artifact install: copying Image/DTB from kernel_out for JetPack $JETPACK_VERSION..."
	shopt -s nullglob
	helper_files=(
		"$SCRIPT_DIRECTORY"/*.sh
		"$SCRIPT_DIRECTORY"/*.txt
		"$SCRIPT_DIRECTORY"/helpers/*.sh
		"$SCRIPT_DIRECTORY"/helpers/*.py
	)
	shopt -u nullglob
	cp "${helper_files[@]}" "$TEGRA_DIR/"
	find "$TEGRA_DIR" -maxdepth 1 -name '*.sh' -type f -exec chmod +x {} +

	KERNEL_BUILD_ARGS=(
		--patch "$JETPACK_VERSION"
		--localversion "-cartken$JETPACK_VERSION"
		--skip-patches
		--only-install-artifacts
		--skip-third-party-drivers
	)

	(
		cd "$TEGRA_DIR"
		sudo ./build_kernel.sh "${KERNEL_BUILD_ARGS[@]}"
	)
	echo "Kernel artifact install completed."
	exit 0
fi

prompt_user

if [[ "$SKIP_PREP" == false ]] && { [ ! -d "$TEGRA_DIR" ] || [ -z "$(ls -A "$TEGRA_DIR" 2>/dev/null)" ]; }; then
	if [ "$DOWNLOAD" = true ]; then
		echo "Downloading required BSP files for JetPack $JETPACK_VERSION (L4T ${JETPACK_L4T_MAP[$JETPACK_VERSION]})..."
		wget -c "${DRIVER_URLS[$JETPACK_VERSION]}" -O "$DRIVER_FILE"
	else
		echo "Skipping download, using local files."
		if [ ! -f "$DRIVER_FILE" ]; then
			echo "Error: Expected file $DRIVER_FILE not found."
			exit 1
		fi
	fi

	prompt_user

	sudo mkdir -p "$TEGRA_BASE_DIR"
	echo "Extracting driver package: $DRIVER_FILE into $TEGRA_BASE_DIR..."
	sudo tar -xjf "$DRIVER_FILE" -C "$TEGRA_BASE_DIR"
	echo "Driver package extracted successfully."
fi

if [[ "$SKIP_PREP" == false ]] && [ -f "$TEGRA_DIR/tools/l4t_flash_prerequisites.sh" ]; then
  echo "Running l4t_flash_prerequisites.sh..."
  (cd "$TEGRA_DIR" && ./tools/l4t_flash_prerequisites.sh)
fi

prompt_user

if [[ "$SKIP_PREP" == false ]] && { [ ! -d "$TEGRA_DIR/kernel_src" ] || [ -z "$(ls -A "$TEGRA_DIR/kernel_src" 2>/dev/null)" ]; }; then

	if [ "$DOWNLOAD" = true ]; then
		echo "Downloading required kernel source files for JetPack $JETPACK_VERSION (L4T ${JETPACK_L4T_MAP[$JETPACK_VERSION]})..."
		wget "${KERNEL_URLS[$JETPACK_VERSION]}" -O "$KERNEL_FILE"
	else
		echo "Skipping download, using local files."
		if [ ! -f "$KERNEL_FILE" ]; then
			echo "Error: Expected file $KERNEL_FILE not found."
			exit 1
		fi
	fi

	prompt_user

	TMP_DIR=$(sudo mktemp -d)
	echo "Extracting public sources: $KERNEL_FILE into $TMP_DIR..."
	sudo tar -xjf "$KERNEL_FILE" -C "$TMP_DIR"
	sudo mkdir -p "$TEGRA_DIR/kernel_src"
	echo "JetPack \"$JETPACK_VERSION\" detected, extracting kernel sources"

	case "$JETPACK_VERSION" in
		5.1.2)
			sudo tar -xjf "$TMP_DIR/Linux_for_Tegra/source/public/kernel_src.tbz2" -C "$TEGRA_DIR/kernel_src"

			if [[ -f "$TMP_DIR/Linux_for_Tegra/source/public/nvidia_kernel_display_driver_source.tbz2" ]]; then
				if [[ ! -d "$TEGRA_DIR/kernel_src/nvdisplay" && ! -d "$TEGRA_DIR/kernel_src/NVIDIA-kernel-module-source-TempVersion" ]]; then
					echo "Extracting NVIDIA kernel display driver source..."
					sudo tar -xjf "$TMP_DIR/Linux_for_Tegra/source/public/nvidia_kernel_display_driver_source.tbz2" -C "$TEGRA_DIR/kernel_src"
					echo "Extraction completed."
				fi

				if [ -d "$TEGRA_DIR/kernel_src/NVIDIA-kernel-module-source-TempVersion" ]; then
					echo "Renaming NVIDIA-kernel-module-source-TempVersion to nvdisplay"
					sudo mv "$TEGRA_DIR/kernel_src/NVIDIA-kernel-module-source-TempVersion" "$TEGRA_DIR/kernel_src/nvdisplay"
				fi
			else
				echo "Warning: nvidia_kernel_display_driver_source.tbz2 not found!"
			fi
			;;
		5.1.3|5.1.4|5.1.5)
			sudo tar -xjf "$TMP_DIR/Linux_for_Tegra/source/public/kernel_src.tbz2" -C "$TEGRA_DIR/kernel_src"

			if [[ -f "$TMP_DIR/Linux_for_Tegra/source/public/nvidia_kernel_display_driver_source.tbz2" ]]; then
				if [ ! -d "$TEGRA_DIR/kernel_src/nvdisplay" ]; then
					echo "Extracting NVIDIA kernel display driver source..."
					sudo tar -xjf "$TMP_DIR/Linux_for_Tegra/source/public/nvidia_kernel_display_driver_source.tbz2" -C "$TEGRA_DIR/kernel_src"
					echo "Extraction completed."
				fi
			else
				echo "Warning: nvidia_kernel_display_driver_source.tbz2 not found!"
			fi
			;;
		6.0DP|6.1|6.2)
			sudo tar -xjf "$TMP_DIR/Linux_for_Tegra/source/kernel_src.tbz2" -C "$TEGRA_DIR/kernel_src"

			if [[ -f "$TMP_DIR/Linux_for_Tegra/source/kernel_oot_modules_src.tbz2" ]]; then
				echo "Extracting kernel out-of-tree modules..."
				if [ ! -d "$TEGRA_DIR/kernel_src/nvidia-oot" ] || [ -z "$(ls -A "$TEGRA_DIR/kernel_src" 2>/dev/null)" ]; then
					sudo tar -xjf "$TMP_DIR/Linux_for_Tegra/source/kernel_oot_modules_src.tbz2" -C "$TEGRA_DIR/kernel_src"
					echo "OOT Modules extracted"
				fi
			else
				echo "Warning: kernel_oot_modules_src.tbz2 not found!"
			fi

			if [[ -f "$TMP_DIR/Linux_for_Tegra/source/nvidia_kernel_display_driver_source.tbz2" ]]; then
				if [ ! -d "$TEGRA_DIR/kernel_src/nvdisplay" ]; then
					echo "Extracting NVIDIA kernel display driver source..."
					sudo tar -xjf "$TMP_DIR/Linux_for_Tegra/source/nvidia_kernel_display_driver_source.tbz2" -C "$TEGRA_DIR/kernel_src"
					echo "Extraction completed."
				fi
			else
				echo "Warning: nvidia_kernel_display_driver_source.tbz2 not found!"
			fi
			;;
		7.2)
			sudo tar -xjf "$TMP_DIR/Linux_for_Tegra/source/kernel_src.tbz2" -C "$TEGRA_DIR/kernel_src"
			extract_jp7_kernel_src_components "$TMP_DIR/Linux_for_Tegra/source" "$TEGRA_DIR/kernel_src"
			;;
		*)
			echo "Error: Unsupported target BSP version. Supported versions are 5.1.2–5.1.5, 6.0DP/6.1/6.2, and 7.2."
			exit 1
			;;
	esac

	echo "Kernel sources extracted successfully."
	rm -rf "$TMP_DIR"
fi

if [[ "$SKIP_PREP" == false ]] && { [ ! -d "$TEGRA_DIR/rootfs" ] || ( [ "$(ls -A "$TEGRA_DIR/rootfs" | grep -v 'README.txt' | wc -l)" -eq 0 ] ); }; then
	if [ "$DOWNLOAD" = true ]; then
		echo "Downloading required rootfs files for JetPack $JETPACK_VERSION (L4T ${JETPACK_L4T_MAP[$JETPACK_VERSION]})..."
		wget -c "${ROOTFS_URLS[$JETPACK_VERSION]}" -O "$ROOTFS_FILE"
	else
		echo "Skipping download, using local files."
		if [ ! -f "$ROOTFS_FILE" ]; then
			echo "Error: Expected file $ROOTFS_FILE not found."
			exit 1
		fi
	fi

	prompt_user

	mkdir -p "$TEGRA_DIR/rootfs"
	echo "Extracting root filesystem: $ROOTFS_FILE into $TEGRA_DIR/rootfs..."
	sudo tar -xjf "$ROOTFS_FILE" -C "$TEGRA_DIR/rootfs"
	echo "Root filesystem extraction completed."
fi

if [[ "$SKIP_PREP" == true && ! -d "$TEGRA_DIR/rootfs" ]]; then
	echo "Error: --skip-prep requested but rootfs is missing at $TEGRA_DIR/rootfs" >&2
	echo "Run once without --skip-prep to initialize this BSP directory." >&2
	exit 1
fi

echo 'export PATH=/usr/local/sbin:/usr/sbin:/sbin:$PATH' | sudo tee $TEGRA_DIR/rootfs/root/.bashrc > /dev/null

# Stage helper scripts into $TEGRA_DIR. Everything lives alongside this script
# in rootfs_prep/ (including jetson_chroot.sh). Copying from local checkout
# (rather than fetching from GitHub master, which we used to do here via the
# contents API + curl/wget) means:
#   - no jq host dep, no GitHub API rate limits
#   - feature-branch edits to these scripts actually run, instead of
#     being silently overwritten by master
#   - works fully offline once the BSP tarballs have been downloaded
echo "Copying rootfs_prep helpers into $TEGRA_DIR..."
shopt -s nullglob
# Sources: top-level entry points + chroot .txts that live at the rootfs_prep
# root, plus the internal helpers under helpers/. We flatten everything into
# $TEGRA_DIR so the chroot driver and the in-rootfs scripts can keep
# referencing each other by basename without caring about the source layout.
helper_files=(
	"$SCRIPT_DIRECTORY"/*.sh
	"$SCRIPT_DIRECTORY"/*.txt
	"$SCRIPT_DIRECTORY"/helpers/*.sh
	"$SCRIPT_DIRECTORY"/helpers/*.py
)
shopt -u nullglob
if [[ ${#helper_files[@]} -eq 0 ]]; then
	echo "Error: no helper scripts found at $SCRIPT_DIRECTORY" >&2
	exit 1
fi
cp "${helper_files[@]}" "$TEGRA_DIR/"
chmod +x "$TEGRA_DIR/jetson_chroot.sh"
if [[ ! -x "$TEGRA_DIR/jetson_chroot.sh" ]]; then
	echo "Error: jetson_chroot.sh not found at $SCRIPT_DIRECTORY/jetson_chroot.sh" >&2
	exit 1
fi

# Stage a JetPack-specific flash driver into Linux_for_Tegra so flashing behavior
# is explicit per major release instead of being hidden in conditional branches.
JP_MAJOR="${JETPACK_VERSION%%.*}"
case "$JP_MAJOR" in
	5) FLASH_VARIANT_DIR="5.X" ;;
	6) FLASH_VARIANT_DIR="6.X" ;;
	7) FLASH_VARIANT_DIR="7.X" ;;
	*) FLASH_VARIANT_DIR="" ;;
esac
if [[ -n "$FLASH_VARIANT_DIR" ]]; then
	FLASH_VARIANT_SRC="$SCRIPT_DIRECTORY/flash_scripts/$FLASH_VARIANT_DIR/flash_jetson_ALL_sdmmc_partition_qspi.sh"
	if [[ ! -f "$FLASH_VARIANT_SRC" ]]; then
		echo "Error: Missing flash script variant: $FLASH_VARIANT_SRC" >&2
		exit 1
	fi
	cp "$FLASH_VARIANT_SRC" "$TEGRA_DIR/flash_jetson_ALL_sdmmc_partition_qspi.sh"
	chmod +x "$TEGRA_DIR/flash_jetson_ALL_sdmmc_partition_qspi.sh"
fi

# Clean up any stale suffixed copies left over from previous runs that used
# the old wget -P behaviour (e.g. chroot_setup_commands.txt.1).
find "$TEGRA_DIR" -maxdepth 1 -regextype posix-extended \
	-regex '.*\.(sh|txt|md)\.[0-9]+' -print -delete || true

prompt_user

if [[ "$SKIP_CHROOT_BUILD" == false && "$SKIP_PREP" == false ]]; then
	echo "Setting up chroot environment for SoC: $SOC..."
	# Pre-apply_binaries pass: just bring the freshly-extracted L4T rootfs to
	# the point where its package manager works. Used to live in
	# essential_chroot_setup_commands.txt - inlined here to keep the chroot
	# .txt set down to the two real things (OS layer + cartken layer).
	ESSENTIAL_APT_META="apt-utils"
	if [[ "$JETPACK_VERSION" == 7.* ]]; then
		# Noble rootfs no longer ships apt-utils as a standalone package.
		ESSENTIAL_APT_META="apt"
	fi
	ESSENTIAL_CMDS_FILE="$(mktemp -p "$TEGRA_DIR" essential_chroot_setup_commands.XXXXXX.txt)"
cat > "$ESSENTIAL_CMDS_FILE" <<EOF
apt-get update -o Acquire::Retries=5 -o APT::Update::Error-Mode=any
apt install -y libglib2.0-0 $ESSENTIAL_APT_META
EOF
	sudo "$TEGRA_DIR/jetson_chroot.sh" "$TEGRA_DIR/rootfs" "$SOC" "$ESSENTIAL_CMDS_FILE"
	rm -f "$ESSENTIAL_CMDS_FILE"
else
	echo "Skipping pre-apply_binaries chroot setup as requested."
fi

# Don't leave a copy of this script inside the BSP — it would shadow the
# canonical version under scripts/flash/rootfs_prep/ if the user ever cd'd
# into $TEGRA_DIR and ran ./setup_tegra_package.sh, and there's no flow
# that needs it there.
rm -f "$TEGRA_DIR/setup_tegra_package.sh"
echo "Setting execute permissions for scripts..."
# Only chmod regular files. NVIDIA ships some top-level .sh as symlinks
# (e.g. l4t_initrd_flash.sh -> tools/kernel_flash/...), which can dangle in
# the JP7 BSP layout; a plain `chmod +x *.sh` then fails on the dangling link
# and, under set -e, aborts the whole setup. -type f matches real files and
# skips symlinks (dangling or not) without erroring.
find "$TEGRA_DIR" -maxdepth 1 -name '*.sh' -type f -exec chmod +x {} +
echo "All rootfs helper scripts staged in $TEGRA_DIR."

prompt_user

cd $TEGRA_DIR
if [[ "$SKIP_PREP" == false ]]; then
	echo "Applying NVIDIA binaries and creating default cartken user..."
	# Inlined from the old setup_rootfs.sh wrapper (which only had one caller,
	# this script, and shared a confusingly similar name with
	# setup_rootfs_as_robot_for_flashing.sh). l4t_flash_prerequisites.sh has
	# already run earlier in this script, so we don't repeat it here.
	echo "Removing existing device nodes before apply_binaries..."
	sudo rm -f "$TEGRA_DIR/rootfs/dev/random"
	sudo rm -f "$TEGRA_DIR/rootfs/dev/urandom"
	sudo "$TEGRA_DIR/apply_binaries.sh"
	echo "Creating default user (cartken/cartken, hostname cart1jetson, autologin)..."
	(
		cd "$TEGRA_DIR/tools"
		sudo ./l4t_create_default_user.sh \
			-u cartken -p cartken -n cart1jetson \
			--autologin --accept-license
	)
else
	echo "Skipping apply_binaries/default-user setup due to --skip-prep."
fi

prompt_user

echo "Running get_packages.sh with access token and tag: $TAG..."
$TEGRA_DIR/get_packages.sh --access-token "$ACCESS_TOKEN" --tag "$TAG"
# Wipe the rootfs's previous packages dir before copying in the freshly-pulled
# set. Without this, a tag that drops a deb leaves stale artefacts at
# /root/packages/ inside the rootfs which then survive into the flashed image.
sudo rm -rf "$TEGRA_DIR/rootfs/root/packages"
sudo cp -r $TEGRA_DIR/packages $TEGRA_DIR/rootfs/root/
RESOLVED_CARTKEN_DEBS_HOST="$(mktemp -p "$TEGRA_DIR" cartken_jetson_debs.resolved.XXXXXX.txt)"
resolve_cartken_manifest_for_packages \
	"$SCRIPT_DIRECTORY/cartken_jetson_debs.txt" \
	"$TEGRA_DIR/packages/cartken-jetson-debians" \
	"$RESOLVED_CARTKEN_DEBS_HOST"
sudo cp "$RESOLVED_CARTKEN_DEBS_HOST" "$TEGRA_DIR/rootfs/root/cartken_jetson_debs.txt"
rm -f "$RESOLVED_CARTKEN_DEBS_HOST"

prompt_user

# The rootfs is built up in two ordered chroot passes, by design:
#   1. OS layer (chroot_install_os_jp{5,6}.txt) - apt deps, nvidia-l4t
#      holds, stock sshd config, etc. JP-specific because JP5 and JP6 have
#      different NVIDIA package names.
#   2. cartken layer (chroot_install_cartken.txt) - single source of truth
#      for cartken-* debs and viki. Self-cleaning: purges every installed
#      cartken-* package before reinstalling the full set, so removing a
#      deb from that file actually removes it from the rootfs next run.
# Both passes also run again from the per-robot scripts
# (setup_rootfs_as_robot_for_flashing.sh / for_ota.sh) so a --tag swap
# rebuilds the cartken layer without re-running this script end to end.
case "$JETPACK_VERSION" in
	5.1.2|5.1.3|5.1.4|5.1.5)
		OS_CHROOT_FILE="chroot_install_os_jp5.txt"
		;;
	6.0DP|6.1|6.2)
		OS_CHROOT_FILE="chroot_install_os_jp6.txt"
		;;
	7.2)
		OS_CHROOT_FILE="chroot_install_os_jp7.txt"
		;;
	*)
		echo "Error: No chroot command file mapping for JetPack $JETPACK_VERSION"
		exit 1
		;;
esac
if [[ "$JETPACK_VERSION" == 7.* ]]; then
	CARTKEN_CHROOT_FILE="chroot_install_cartken_jp7.txt"
else
	CARTKEN_CHROOT_FILE="chroot_install_cartken.txt"
fi

if [[ "$SKIP_CHROOT_BUILD" == false ]]; then
	echo "Pass 1/2: OS layer chroot for SoC=$SOC using $OS_CHROOT_FILE..."
	sudo $TEGRA_DIR/jetson_chroot.sh rootfs "$SOC" "$OS_CHROOT_FILE"
	echo "Pass 2/2: cartken layer chroot for SoC=$SOC using $CARTKEN_CHROOT_FILE..."
	sudo $TEGRA_DIR/jetson_chroot.sh rootfs "$SOC" "$CARTKEN_CHROOT_FILE"
else
	echo "Skipping rootfs setup in chroot as requested."
fi

prompt_user

if [[ "$SKIP_PINMUX" == false ]]; then
	echo "Getting pinmux files"
	PINMUX_MAJOR="${JETPACK_VERSION%%.*}.X"
	for PINMUX_BUNDLE_SRC in \
		"$SCRIPT_DIRECTORY/helpers/pinmux/$PINMUX_MAJOR" \
		"$SCRIPT_DIRECTORY/../../../sources/pinmux/$PINMUX_MAJOR"; do
		if [[ -d "$PINMUX_BUNDLE_SRC" ]]; then
			rm -rf "$TEGRA_DIR/.cartken_pinmux"
			cp -r "$PINMUX_BUNDLE_SRC" "$TEGRA_DIR/.cartken_pinmux"
			echo "Staged pinmux bundle at $TEGRA_DIR/.cartken_pinmux from $PINMUX_BUNDLE_SRC"
			break
		fi
	done
	cp "$SCRIPT_DIRECTORY/helpers/get_pinmux.sh" "$TEGRA_DIR/get_pinmux.sh"
	chmod +x "$TEGRA_DIR/get_pinmux.sh"
	sudo $TEGRA_DIR/get_pinmux.sh --l4t-dir $TEGRA_DIR --jetpack-version $JETPACK_VERSION
else
	echo "Skipping pinmux override as requested."
fi

if [[ "$JUST_CLONE" == true ]]; then
	exit 1
fi

prompt_user

if [[ "$SKIP_KERNEL_BUILD" == false || ( "$JETPACK_VERSION" != 6.* && "$JETPACK_VERSION" != 7.* && "$SKIP_DISPLAY_DRIVER_BUILD" == false ) ]]; then
		if [[ "$JETPACK_VERSION" != 7.* ]]; then
			echo "Cloning Jetson Linux toolchain into $TEGRA_DIR/toolchain..."
			if [ ! -d "$TEGRA_DIR/toolchain" ]; then
				sudo git clone --config core.symlinks=true --depth=1 https://github.com/alxhoff/jetson-linux-toolchain "$TEGRA_DIR/toolchain"
			fi
			echo "Toolchain cloned successfully."
		else
			echo "JP7 kernel builds use NVIDIA Crosstool-NG GCC 13.2 from the Docker image or toolchains/jp7/."
		fi
	
		prompt_user
	fi

	if [[ "$SKIP_KERNEL_BUILD" == false ]]; then
		if [[ "$JETPACK_VERSION" == 7.* ]]; then
			ensure_jp7_kernel_src_complete "$TEGRA_DIR/kernel_src" "$KERNEL_FILE"
		fi
		echo "Building kernel"
		case "$JETPACK_VERSION" in
			5.1.2|5.1.3|5.1.4|5.1.5|6.0DP|6.1|6.2|7.2)
				KERNEL_BUILD_ARGS=(--patch "$JETPACK_VERSION" --localversion "-cartken$JETPACK_VERSION")
				sudo "$TEGRA_DIR/build_kernel.sh" "${KERNEL_BUILD_ARGS[@]}"
				;;
			*)
				echo "Error: Unsupported JetPack version for kernel build."
				exit 1
				;;
		esac
	else
		echo "Skipping kernel build as requested."
	fi
	
	prompt_user

	if [[ "$SKIP_DISPLAY_DRIVER_BUILD" == false ]]; then
		case "$JETPACK_VERSION" in
			5.1.2|5.1.3|5.1.4|5.1.5)
				echo "Building display driver"
				echo "sudo "$TEGRA_DIR/build_display_driver.sh" --toolchain "$TEGRA_DIR/toolchain" --kernel-sources "$TEGRA_DIR/kernel_src" --target-bsp "$JETPACK_VERSION""
				sudo "$TEGRA_DIR/build_display_driver.sh" --toolchain "$TEGRA_DIR/toolchain" --kernel-sources "$TEGRA_DIR/kernel_src" --target-bsp "$JETPACK_VERSION"
	
				prompt_user
	
				DISPLAY_DRIVER_DIR="$TEGRA_DIR/jetson_display_driver"
				ROOTFS_DIR="$TEGRA_DIR/rootfs"
				ROOTFS_MODULES_DIR="$ROOTFS_DIR/lib/modules"
				KERNEL_VERSION=$(find "$DISPLAY_DRIVER_DIR" -type f -name "Image" -exec strings {} \; | grep -m1 -Eo 'Linux version [^ ]+' | awk '{print $3}')
				ROOTFS_TARGET_MODULES_DIR="$ROOTFS_MODULES_DIR/$KERNEL_VERSION/extra/opensrc-disp"
				echo "Copying display driver into our kernel at $ROOTFS_TARGET_MODULES_DIR"
				mkdir -p "$ROOTFS_TARGET_MODULES_DIR"
				NVDISPLAY_MOD_DIR=$(find "$DISPLAY_DRIVER_DIR" -type f -name "nvidia.ko" -exec dirname {} \; | head -n1)
				echo "nvidia.ko found in: $NVDISPLAY_MOD_DIR"
				cp "$NVDISPLAY_MOD_DIR"/*.ko "$ROOTFS_TARGET_MODULES_DIR"
	
				echo "Running depmod on $KERNEL_VERSION for rootfs: $ROOTFS_DIR"
				depmod -b "$ROOTFS_DIR" "$KERNEL_VERSION"
				;;
			6.0DP|6.1|6.2|7.2)
				echo "Display driver build is part of kernel build for JetPack 6.x/7.x, cannot be skipped separately."
				;;
			*)
				echo "Error: Unsupported JetPack version for kernel build."
				exit 1
				;;
		esac
	else
		echo "Skipping display driver build as requested."
	fi

echo "Setup completed successfully!"
