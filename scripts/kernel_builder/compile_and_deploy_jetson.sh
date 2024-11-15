#!/bin/bash

# Example workflow for compiling and optionally deploying a Jetson kernel
# Usage: ./compile_and_deploy_jetson.sh [OPTIONS]
# Description:
# This script automates the process of compiling a custom Jetson kernel and optionally deploying it to a Jetson device.
# It first compiles the kernel, and if deployment is enabled, it deploys the compiled kernel and associated modules to the specified device.

# Options:
#   --help               Display this help message with examples.
#   --no-deploy          Skip deploying the kernel to the device. Only compile the kernel.
#   --config <file>      Specify the kernel configuration file to use during the build.
#   --localversion <str> Set a custom local version string during kernel compilation. If not provided, a default string is generated.
#   --dry-run            Simulate the compilation and/or deployment processes without actually executing them. Useful for debugging.
#   --threads <number>   Specify the number of threads to use during kernel compilation for better performance.
#
# Examples:
#   1. Compile and deploy the kernel to a Jetson device with a custom configuration file:
#      ./compile_and_deploy_jetson.sh --config tegra_defconfig --localversion custom_version
#
#   2. Compile the kernel only (skip deployment):
#      ./compile_and_deploy_jetson.sh --no-deploy --localversion custom_version
#
#   3. Compile with 4 threads and deploy to Jetson device:
#      ./compile_and_deploy_jetson.sh --threads 4
#
#   4. Perform a dry-run (only print commands without executing them):
#      ./compile_and_deploy_jetson.sh --dry-run --localversion custom_version

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 [OPTIONS]"
  echo "Try '$0 --help' for more information."
  exit 1
fi

if [[ "$1" == "--help" ]]; then
  echo "
  Usage: ./compile_and_deploy_jetson.sh [OPTIONS]
  Description:
    This script automates the process of compiling a custom Jetson kernel and optionally deploying it to a Jetson device.
    It first compiles the kernel, and if deployment is enabled, it deploys the compiled kernel and associated modules to the specified device.

  Options:
    --help               Display this help message with examples.
    --no-deploy          Skip deploying the kernel to the device. Only compile the kernel.
    --config <file>      Specify the kernel configuration file to use during the build.
    --localversion <str> Set a custom local version string during kernel compilation. If not provided, a default string is generated.
    --dry-run            Simulate the compilation and/or deployment processes without actually executing them. Useful for debugging.
    --threads <number>   Specify the number of threads to use during kernel compilation for better performance.

  Examples:
    1. Compile and deploy the kernel to a Jetson device with a custom configuration file:
       ./compile_and_deploy_jetson.sh --config tegra_defconfig --localversion custom_version

    2. Compile the kernel only (skip deployment):
       ./compile_and_deploy_jetson.sh --no-deploy --localversion custom_version

    3. Compile with 4 threads and deploy to Jetson device:
       ./compile_and_deploy_jetson.sh --threads 4

    4. Perform a dry-run (only print commands without executing them):
       ./compile_and_deploy_jetson.sh --dry-run --localversion custom_version
  "
  exit 0
fi

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_BUILDER_SCRIPT="$SCRIPT_DIR/kernel_builder/compile_jetson_kernel.sh"
DEPLOY_SCRIPT="$SCRIPT_DIR/kernel_builder/deploy_only_jetson.sh"

# Check arguments
NO_DEPLOY=false
CONFIG_ARG=""
LOCALVERSION_ARG=""
DRY_RUN=false
THREADS_ARG=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --no-deploy)
      NO_DEPLOY=true
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

# Read the device IP and username from files, if they exist
DEVICE_IP=""
USERNAME="cartken" # default username

if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(<"$SCRIPT_DIR/device_ip")
fi

if [ -f "$SCRIPT_DIR/device_username" ]; then
  USERNAME=$(<"$SCRIPT_DIR/device_username")
fi

# Compile the kernel using the compile_jetson_kernel.sh script
if ! "$KERNEL_BUILDER_SCRIPT" --localversion "$LOCALVERSION_ARG" $CONFIG_ARG $THREADS_ARG; then
  echo "Kernel compilation failed. Aborting deployment."
  exit 1
fi

# Deploy to Jetson device (if not skipped)
if [ "$NO_DEPLOY" == false ]; then
  if [ -z "$DEVICE_IP" ]; then
    echo "Error: Device IP is required to deploy the kernel. Please provide it in the device_ip file."
    exit 1
  fi

  # Prepare deploy command with the correct options
  DEPLOY_COMMAND="$DEPLOY_SCRIPT --ip $DEVICE_IP --user $USERNAME"
  [ "$DRY_RUN" == true ] && DEPLOY_COMMAND+=" --dry-run"
  DEPLOY_COMMAND+=" --localversion $LOCALVERSION_ARG"

  # Execute deployment command
  echo "Deploying compiled kernel to the Jetson device at $DEVICE_IP..."
  if ! eval $DEPLOY_COMMAND; then
    echo "Failed to deploy the compiled kernel to the Jetson device at $DEVICE_IP"
    exit 1
  fi
fi

echo "Kernel compilation and deployment (if applicable) completed successfully."

