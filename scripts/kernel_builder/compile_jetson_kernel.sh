#!/bin/bash

# Example workflow for compiling a Jetson kernel and specifying the DTB file
# Usage: ./compile_jetson_kernel.sh [OPTIONS]

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_BUILDER_PATH="$SCRIPT_DIR/../kernel_builder.py"

# Initialize arguments
CONFIG_ARG=""
LOCALVERSION_ARG=""
THREADS_ARG=""
DTB_NAME_ARG="--dtb-name tegra234-p3701-0000-p3737-0000.dtb"  # Default DTB name
HOST_BUILD_ARG=""
DRY_RUN_ARG=""

# Function to display help message
show_help() {
    echo "Usage: ./compile_jetson_kernel.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --config <config-file>         Specify the kernel configuration file to use (e.g., defconfig, tegra_defconfig)."
    echo "  --localversion <version>       Set a local version string to append to the kernel version (e.g., -custom_version)."
    echo "  --threads <number>             Number of threads to use for compilation (default: use all available cores)."
    echo "  --dtb-name <dtb-name>          Specify the name of the Device Tree Blob (DTB) file to be copied alongside the compiled kernel (default: tegra234-p3701-0000-p3737-0000.dtb)."
    echo "  --host-build                   Compile the kernel directly on the host instead of using Docker."
    echo "  --dry-run                      Print the commands without executing them."
    echo "  --help                         Display this help message and exit."
    echo ""
    echo "Examples:"
    echo "  Compile with default settings:"
    echo "    ./compile_jetson_kernel.sh"
    echo ""
    echo "  Compile using a specific kernel config and local version:"
    echo "    ./compile_jetson_kernel.sh --config tegra_defconfig --localversion custom_version"
    echo ""
    echo "  Compile with 8 threads and specify a DTB file:"
    echo "    ./compile_jetson_kernel.sh --threads 8 --dtb-name tegra234-p3701-0000-p3737-0000.dtb"
    echo ""
    echo "  Compile directly on the host system instead of using Docker:"
    echo "    ./compile_jetson_kernel.sh --host-build"
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
        LOCALVERSION_ARG="--localversion $2"
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
    --dtb-name)
      if [ -n "$2" ]; then
        DTB_NAME_ARG="--dtb-name $2"
        shift 2
      else
        echo "Error: --dtb-name requires a value"
        exit 1
      fi
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
      exit 1
      ;;
  esac
done

# Compile the kernel using kernel_builder.py
COMMAND="python3 \"$KERNEL_BUILDER_PATH\" compile --kernel-name jetson --arch arm64 --toolchain-name aarch64-buildroot-linux-gnu $CONFIG_ARG $THREADS_ARG $LOCALVERSION_ARG $DTB_NAME_ARG $HOST_BUILD_ARG $DRY_RUN_ARG"

# Execute the command
echo "Running: $COMMAND"
if [[ -n "$DRY_RUN_ARG" ]]; then
  echo "[Dry-run] Command: $COMMAND"
else
  eval $COMMAND
fi

