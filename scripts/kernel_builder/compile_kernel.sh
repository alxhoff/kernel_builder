#!/bin/bash

# General workflow for compiling a kernel, specifying the kernel to be built.
# Usage: ./compile_kernel.sh [KERNEL_NAME] [OPTIONS]

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_BUILDER_PATH="$SCRIPT_DIR/../kernel_builder.py"

set -e

# Ensure kernel name is provided
if [ -z "$1" ]; then
  echo "Error: Kernel name must be provided as the first argument."
  echo "Usage: ./compile_kernel.sh [KERNEL_NAME] [OPTIONS]"
  echo "Use --help for more information."
  exit 1
fi

KERNEL_NAME="$1"
shift # Shift arguments to parse the rest of the options

# Initialize arguments
CONFIG_ARG=""
LOCALVERSION_ARG=""
THREADS_ARG=""
BUILD_TARGET_ARG=""
DTB_NAME_ARG="--dtb-name tegra234-p3701-0000-p3737-0000.dtb"  # Default DTB name
BUILD_DTB_ARG=""
HOST_BUILD_ARG=""
DRY_RUN_ARG=""

# Function to display help message
show_help() {
    echo "Usage: ./compile_kernel.sh [KERNEL_NAME] [OPTIONS]"
    echo ""
    echo "Arguments:"
    echo "  KERNEL_NAME                    Specify the name of the kernel to be built (e.g., 'jetson')."
    echo ""
    echo "Options:"
    echo "  --config <config-file>         Specify the kernel configuration file to use (e.g., defconfig, tegra_defconfig)."
    echo "  --localversion <version>       Set a local version string to append to the kernel version (e.g., -custom_version)."
    echo "  --threads <number>             Number of threads to use for compilation (default: use all available cores)."
    echo "  --build-target <target>        Specify the make target for the kernel build (e.g., 'kernel', 'modules', 'dtbs')."
    echo "  --dtb-name <dtb-name>          Specify the name of the Device Tree Blob (DTB) file to be copied alongside the compiled kernel (default: tegra234-p3701-0000-p3737-0000.dtb)."
    echo "  --build-dtb                    Build the Device Tree Blob (DTB) separately using 'make dtbs'."
    echo "  --host-build                   Compile the kernel directly on the host instead of using Docker."
    echo "  --dry-run                      Print the commands without executing them."
    echo "  --help                         Display this help message and exit."
    echo ""
    echo "Examples:"
    echo "  Compile a kernel named 'jetson' with default settings:"
    echo "    ./compile_kernel.sh jetson"
    echo ""
    echo "  Compile a kernel using a specific kernel config and local version:"
    echo "    ./compile_kernel.sh jetson --config tegra_defconfig --localversion custom_version"
    echo ""
    echo "  Compile a kernel with 8 threads and specify a DTB file:"
    echo "    ./compile_kernel.sh jetson --threads 8 --dtb-name tegra234-p3701-0000-p3737-0000.dtb"
    echo ""
    echo "  Compile directly on the host system instead of using Docker:"
    echo "    ./compile_kernel.sh jetson --host-build"
    echo ""
    exit 0
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --config)
      if [ -n "$2" ]; then
        CONFIG_ARG="--config $2"
        shift 2
      else
        echo "Error: --config requires a value"
        exit 1
      fi
      ;;
    --localversion)
      if [ -n "$2" ]; then
        LOCALVERSION_ARG="--localversion "$2""
        shift 2
      else
        echo "Error: --localversion requires a value"
        exit 1
      fi
      ;;
    --threads)
      if [ -n "$2" ]; then
        THREADS_ARG="--threads $2"
        shift 2
      else
        echo "Error: --threads requires a value"
        exit 1
      fi
      ;;
    --build-target)
      if [ -n "$2" ]; then
        BUILD_TARGET_ARG="--build-target $2"
        shift 2
      else
        echo "Error: --build-target requires a value"
        exit 1
      fi
      ;;
    --dtb-name)
      if [ -n "$2" ]; then
        DTB_NAME_ARG="--dtb-name $2"
        shift 2
      else
        echo "Error: --dtb-name requires a value"
        exit 1
      fi
      ;;
    --build-dtb)
      BUILD_DTB_ARG="--build-dtb"
      shift
      ;;
    --host-build)
      HOST_BUILD_ARG="--host-build"
      shift
      ;;
    --dry-run)
      DRY_RUN_ARG="--dry-run"
      shift
      ;;
    --help)
      show_help
      ;;
    *)
      echo "Unknown parameter: $1"
      echo "Use --help for more information."
      exit 1
      ;;
  esac
done

# Compile the kernel using kernel_builder.py
COMMAND="python3 "$KERNEL_BUILDER_PATH" compile --kernel-name "$KERNEL_NAME" --arch arm64 --toolchain-name aarch64-buildroot-linux-gnu $CONFIG_ARG $THREADS_ARG $LOCALVERSION_ARG $DTB_NAME_ARG $HOST_BUILD_ARG $DRY_RUN_ARG $BUILD_TARGET_ARG $BUILD_DTB_ARG"

# Execute the command
echo "Running: $COMMAND"
if [[ -n "$DRY_RUN_ARG" ]]; then
  echo "[Dry-run] Command: $COMMAND"
else
  eval $COMMAND
fi