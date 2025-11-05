#!/bin/bash

# Script to compile only the modules for a Jetson kernel
# Usage: ./compile_jetson_modules.sh [--config <config-file>] [--localversion <version>] [--threads <number>] [--toolchain-name <name>] [--toolchain-version <version>]

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_BUILDER_PATH="$SCRIPT_DIR/../kernel_builder.py"

# Initialize arguments
CONFIG_ARG=""
LOCALVERSION_ARG=""
THREADS_ARG=""
TOOLCHAIN_NAME_ARG="--toolchain-name aarch64-buildroot-linux-gnu"
TOOLCHAIN_VERSION_ARG="--toolchain-version 9.3"

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
    --toolchain-name)
      if [ -n "$2" ]; then
        TOOLCHAIN_NAME_ARG="--toolchain-name $2"
        shift 2
      else
        echo "Error: --toolchain-name requires a value"
        exit 1
      fi
      ;;
    --toolchain-version)
      if [ -n "$2" ]; then
        TOOLCHAIN_VERSION_ARG="--toolchain-version $2"
        shift 2
      else
        echo "Error: --toolchain-version requires a value"
        exit 1
      fi
      ;;
    *)
      echo "Unknown parameter: $1"
      exit 1
      ;;
  esac
done

# Compile the kernel modules using kernel_builder.py
COMMAND="python3 \"$KERNEL_BUILDER_PATH\" compile --kernel-name jetson --arch arm64 $TOOLCHAIN_NAME_ARG $TOOLCHAIN_VERSION_ARG --build-target modules $CONFIG_ARG $THREADS_ARG"
[ -n "$LOCALVERSION_ARG" ] && COMMAND+=" $LOCALVERSION_ARG"

# Execute the command
echo "Running: $COMMAND"
eval $COMMAND

