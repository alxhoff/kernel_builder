#!/bin/bash

# Example workflow for compiling and packaging a kernel into a Debian package
# Usage: ./compile_and_package.sh [KERNEL_NAME] [OPTIONS]

set -e

# Ensure kernel name is provided
if [ -z "$1" ]; then
  echo "Error: Kernel name must be provided as the first argument."
  echo "Usage: ./compile_and_package.sh [KERNEL_NAME] [OPTIONS]"
  exit 1
fi

KERNEL_NAME="$1"
shift # Shift arguments to parse the rest of the options

# Set script paths
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_BUILDER_SCRIPT="$SCRIPT_DIR/kernel_builder/compile_kernel.sh"
DEPLOY_SCRIPT="$SCRIPT_DIR/kernel_builder/deploy_debian.sh"

# Parse arguments
CONFIG_ARG=""
DTB_NAME_ARG=""
LOCALVERSION_ARG=""
DRY_RUN=false
THREADS_ARG=""

# Function to display help
show_help() {
  echo "
  Usage: ./compile_and_package.sh [KERNEL_NAME] [OPTIONS]
  Description:
    This script automates the process of compiling a custom kernel and packaging it into a Debian package.

  Options:
    --help               Display this help message.
    --config <file>      Specify the kernel configuration file to use during the build.
    --localversion <str> Set a custom local version string during kernel compilation.
    --dry-run            Simulate the compilation and packaging processes without executing them.
    --threads <number>   Specify the number of threads to use during kernel compilation.
	--dtb-name <name>    Specify a DTB filename to build.

  Examples:
    1. Compile and package the kernel with a custom configuration file:
       ./compile_and_package.sh jetson --config tegra_defconfig --localversion custom_version

    2. Compile the kernel only (skip packaging):
       ./compile_and_package.sh jetson --localversion custom_version

    3. Compile with 4 threads:
       ./compile_and_package.sh jetson --threads 4

    4. Perform a dry-run (only print commands without executing them):
       ./compile_and_package.sh jetson --dry-run --localversion custom_version
  "
  exit 0
}

# Check if --help is passed
if [[ "$1" == "--help" ]]; then
    show_help
fi

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
        LOCALVERSION_ARG="$2"
        shift 2
      else
        echo "Error: --localversion requires a value"
        exit 1
      fi
      ;;
    --dry-run)
      DRY_RUN=true
      shift
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
    *)
      echo "Invalid argument: $1"
      exit 1
      ;;
  esac
done

# If LOCALVERSION is not provided, create a default one
if [ -z "$LOCALVERSION_ARG" ]; then
  LOCALVERSION_ARG="custom_$(date +%Y_%m_%d__%H_%M)"
fi

# Compile the kernel
if ! "$KERNEL_BUILDER_SCRIPT" "$KERNEL_NAME" --localversion "$LOCALVERSION_ARG" $CONFIG_ARG $THREADS_ARG $DTB_NAME_ARG; then
  echo "Kernel compilation failed."
  exit 1
fi

# Build the Debian package
echo "Building Debian package for kernel: $KERNEL_NAME (localversion: $LOCALVERSION_ARG)"
CMD="\"$DEPLOY_SCRIPT\" \"$KERNEL_NAME\" --localversion \"$LOCALVERSION_ARG\" $DTB_NAME_ARG"

echo "Running command: $CMD"

if ! eval $CMD; then
  echo "Failed to create Debian package."
  exit 1
fi

echo "Kernel compilation and packaging completed successfully."

