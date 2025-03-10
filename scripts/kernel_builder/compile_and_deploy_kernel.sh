#!/bin/bash

# Example workflow for compiling and optionally deploying a kernel
# Usage: ./compile_and_deploy_kernel.sh [KERNEL_NAME] [OPTIONS]
# Description:
# This script automates the process of compiling a custom kernel and optionally deploying it to a device.
set -e

# Ensure kernel name is provided
if [ -z "$1" ]; then
  echo "Error: Kernel name must be provided as the first argument."
  echo "Usage: ./compile_and_deploy_kernel.sh [KERNEL_NAME] [OPTIONS]"
  echo "Use --help for more information."
  exit 1
fi

KERNEL_NAME="$1"
shift # Shift arguments to parse the rest of the options

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_BUILDER_SCRIPT="$SCRIPT_DIR/kernel_builder/compile_kernel.sh"
DEPLOY_SCRIPT="$SCRIPT_DIR/kernel_builder/deploy_kernel.sh"

# Check arguments
NO_DEPLOY=false
CONFIG_ARG=""
LOCALVERSION_ARG=""
DRY_RUN=false
THREADS_ARG=""
KERNEL_ONLY=false
DTB_FLAG=false

# Function to display help
show_help() {
  echo "
  Usage: ./compile_and_deploy_kernel.sh [KERNEL_NAME] [OPTIONS]
  Description:
    This script automates the process of compiling a custom kernel and optionally deploying it to a device.
    It first compiles the kernel, and if deployment is enabled, it deploys the compiled kernel and associated modules to the specified device.

  Options:
    --help               Display this help message with examples.
    --no-deploy          Skip deploying the kernel to the device. Only compile the kernel.
    --kernel-only        Only deploy the kernel image, skipping module deployment.
    --config <file>      Specify the kernel configuration file to use during the build.
    --localversion <str> Set a custom local version string during kernel compilation. If not provided, a default string is generated.
    --dry-run            Simulate the compilation and/or deployment processes without actually executing them. Useful for debugging.
    --threads <number>   Specify the number of threads to use during kernel compilation for better performance.
    --dtb                Set the newly compiled DTB as the default in the boot configuration.

  Examples:
    1. Compile and deploy the kernel to a device with a custom configuration file:
       ./compile_and_deploy_kernel.sh jetson --config tegra_defconfig --localversion custom_version

    2. Compile the kernel only (skip deployment):
       ./compile_and_deploy_kernel.sh jetson --no-deploy --localversion custom_version

    3. Compile with 4 threads and deploy to device:
       ./compile_and_deploy_kernel.sh jetson --threads 4

    4. Perform a dry-run (only print commands without executing them):
       ./compile_and_deploy_kernel.sh jetson --dry-run --localversion custom_version
  "
  exit 0
}

# Check if --help is passed
if [[ "$1" == "--help" ]]; then
    show_help
fi

# Read the device IP and username from files, if they exist
DEVICE_IP=""
USERNAME="cartken" # default username

if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(<"$SCRIPT_DIR/device_ip")
fi

if [ -f "$SCRIPT_DIR/device_username" ]; then
  USERNAME=$(<"$SCRIPT_DIR/device_username")
fi

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --no-deploy)
      NO_DEPLOY=true
      shift
      ;;
    --kernel-only)
      KERNEL_ONLY=true
      shift
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
    --dtb)
      DTB_FLAG=true
      shift
      ;;
    *)
      echo "Invalid argument: $1"
      exit 1
      ;;
  esac
done

# If LOCALVERSION is not provided, create a default one
if [ -z "$LOCALVERSION_ARG" ]; then
  LOCALVERSION_ARG="cartken_$(date +%Y_%m_%d__%H_%M)"
fi

# Compile the kernel using the compile_kernel.sh script
if ! "$KERNEL_BUILDER_SCRIPT" "$KERNEL_NAME" --localversion "$LOCALVERSION_ARG" $CONFIG_ARG $THREADS_ARG; then
  echo "Kernel compilation failed. Aborting deployment."
  exit 1
fi

# Deploy to device (if not skipped)
if [ "$NO_DEPLOY" == false ]; then
  if [ -z "$DEVICE_IP" ]; then
    echo "Error: Device IP is required to deploy the kernel. Please provide it in the device_ip file."
    exit 1
  fi

  # Prepare deploy command with the correct options
  DEPLOY_COMMAND="$DEPLOY_SCRIPT "$KERNEL_NAME" --ip $DEVICE_IP --user $USERNAME"
  [ "$DRY_RUN" == true ] && DEPLOY_COMMAND+=" --dry-run"
  DEPLOY_COMMAND+=" --localversion "$LOCALVERSION_ARG""
  [ "$KERNEL_ONLY" == true ] && DEPLOY_COMMAND+=" --kernel-only"
  [ "$DTB_FLAG" == true ] && DEPLOY_COMMAND+=" --dtb"

  # Execute deployment command
  echo "Deploying compiled kernel to the device at $DEVICE_IP..."
  if ! eval $DEPLOY_COMMAND; then
    echo "Failed to deploy the compiled kernel to the device at $DEVICE_IP"
    exit 1
  fi
fi

echo "Kernel compilation and deployment (if applicable) completed successfully."

