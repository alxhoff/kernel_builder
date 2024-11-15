#!/bin/bash

# Example workflow for compiling a Jetson kernel
# Usage: ./compile_jetson_kernel.sh [--config <config-file>] [--localversion <version>] [--threads <number>] [--host-build] [--dry-run] [--help]

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_BUILDER_PATH="$SCRIPT_DIR/../kernel_builder.py"

# Initialize arguments
CONFIG_ARG=""
LOCALVERSION_ARG=""
THREADS_ARG=""
HOST_BUILD_ARG=""
DRY_RUN_ARG=""

function show_help {
  echo "Usage: ./compile_jetson_kernel.sh [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --config <config-file>      Specify the kernel configuration file to use (e.g., defconfig, tegra_defconfig)."
  echo "  --localversion <version>    Set a local version string to append to the kernel version."
  echo "  --threads <number>          Number of threads to use for compilation. Default: All available cores."
  echo "  --host-build                Compile the kernel directly on the host instead of using Docker."
  echo "  --dry-run                   Print the commands without executing them."
  echo "  --help                      Show this help message."
  echo ""
  echo "Examples:"
  echo "  Compile the Jetson kernel with a specific configuration:"
  echo "    ./compile_jetson_kernel.sh --config tegra_defconfig"
  echo ""
  echo "  Compile the Jetson kernel with a local version string and 8 threads:"
  echo "    ./compile_jetson_kernel.sh --localversion custom_version --threads 8"
  echo ""
  echo "  Compile the kernel directly on the host system:"
  echo "    ./compile_jetson_kernel.sh --host-build"
  echo ""
  echo "  Perform a dry run to print commands without executing them:"
  echo "    ./compile_jetson_kernel.sh --config tegra_defconfig --dry-run"
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
COMMAND="python3 \"$KERNEL_BUILDER_PATH\" compile --kernel-name jetson --arch arm64 --toolchain-name aarch64-buildroot-linux-gnu $CONFIG_ARG $THREADS_ARG $LOCALVERSION_ARG $HOST_BUILD_ARG $DRY_RUN_ARG"

# Execute the command
echo "Running: $COMMAND"
if [[ -n "$DRY_RUN_ARG" ]]; then
  echo "[Dry-run] Command: $COMMAND"
else
  eval $COMMAND
fi

