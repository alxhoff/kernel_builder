#!/bin/bash

# compile_targeted_modules.sh
# Script to build targeted modules for a Jetson device
# Usage: ./compile_targeted_modules.sh --kernel-name <kernel-name> [--config <config-file>] [--localversion <version>] [--threads <number>] [--host-build]
# Arguments:
#   --kernel-name   Required argument to specify the kernel folder name to use
#   --config        Optional argument to specify the kernel configuration file to use
#   --localversion  Optional argument to set a custom local version string during kernel compilation
#   --threads       Optional argument to specify the number of threads to use during kernel compilation
#   --host-build    Optional argument to perform the build on the host machine instead of using Docker

if [[ "$1" == "--help" ]]; then
  echo "Usage: ./compile_targeted_modules.sh [OPTIONS]"
  echo ""
  echo "Build targeted kernel modules for a device. The modules to be built must be specified in a file called 'target_modules.txt', which should be located in the same directory as this script."
  echo ""
  echo "Options:"
  echo "  --kernel-name            Name of the kernel folder to use (required)."
  echo "  --config <config-file>   Specify the kernel configuration file to use during the build."
  echo "  --localversion <version> Set a custom local version string during kernel compilation."
  echo "  --threads <number>       Specify the number of threads to use during kernel compilation (default: use all available cores)."
  echo "  --host-build             Perform the build on the host machine instead of using Docker."
  echo "  --help                   Show this help message and exit."
  echo ""
  echo "Examples:"
  echo "  ./compile_targeted_modules.sh --kernel-name jetson --config defconfig --localversion custom_version --threads 4"
  echo "  ./compile_targeted_modules.sh --kernel-name jetson --host-build"
  echo ""
  echo "Note: The list of target modules must be specified in the 'target_modules.txt' file."
  exit 0
fi

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_BUILDER_SCRIPT="$SCRIPT_DIR/../kernel_builder.py"

# Check arguments
KERNEL_NAME=""
CONFIG_ARG=""
LOCALVERSION_ARG=""
THREADS_ARG=""
HOST_BUILD=false

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --kernel-name)
      if [ -n "$2" ]; then
        KERNEL_NAME="$2"
        shift 2
      else
        echo "Error: --kernel-name requires a value"
        exit 1
      fi
      ;;
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
      HOST_BUILD=true
      shift
      ;;
    *)
      echo "Invalid argument: $1"
      exit 1
      ;;
  esac
done

# Validate required arguments
if [ -z "$KERNEL_NAME" ]; then
  echo "Error: --kernel-name is required."
  exit 1
fi

# Set default local version if not provided
if [ -z "$LOCALVERSION_ARG" ]; then
  LOCALVERSION_ARG="cartken_$(date +%Y_%m_%d__%H_%M)"
fi

# Build the targeted modules using kernel_builder.py with compile-target-modules
COMMAND="python3 \"$KERNEL_BUILDER_SCRIPT\" compile-target-modules --kernel-name $KERNEL_NAME --arch arm64 --toolchain-name aarch64-buildroot-linux-gnu $CONFIG_ARG $LOCALVERSION_ARG $THREADS_ARG"
[ "$HOST_BUILD" == true ] && COMMAND+=" --host-build"

echo "Running: $COMMAND"
eval $COMMAND

