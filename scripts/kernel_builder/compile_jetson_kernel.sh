#!/bin/bash

# Example workflow for compiling a Jetson kernel
# Usage: ./compile_jetson_kernel.sh [--config <config-file>] [--localversion <version>] [--threads <number>] [--host-build] [--dry-run]

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_BUILDER_PATH="$SCRIPT_DIR/../kernel_builder.py"

# Initialize arguments
CONFIG_ARG=""
LOCALVERSION_ARG=""
THREADS_ARG=""
HOST_BUILD_ARG=""
DRY_RUN_ARG=""

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

