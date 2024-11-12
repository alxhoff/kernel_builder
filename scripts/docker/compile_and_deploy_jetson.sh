#!/bin/bash

# Example workflow for compiling and optionally deploying a Jetson kernel
# Usage: ./compile_and_deploy_jetson.sh [--no-deploy] [--config <config-file>] [--localversion <version>] [--dry-run] [--threads <number>]
# Arguments:
#   --no-deploy     Optional argument to skip deploying the kernel to the device
#   --config        Optional argument to specify the kernel configuration file to use
#   --localversion  Optional argument to set a custom local version string during kernel compilation
#   --dry-run       Optional argument to simulate the deployment process without copying anything to the Jetson device
#   --threads       Optional argument to specify the number of threads to use during kernel compilation

if [ "$#" -gt 6 ]; then
  echo "Usage: $0 [--no-deploy] [--config <config-file>] [--localversion <version>] [--dry-run] [--threads <number>]"
  exit 1
fi

# Set the script directory to be one level up from the current script's directory
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
KERNEL_BUILDER_SCRIPT="$SCRIPT_DIR/docker/compile_jetson_kernel.sh"
DEPLOY_SCRIPT="$SCRIPT_DIR/docker/deploy_only_jetson.sh"

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
        LOCALVERSION_ARG="--localversion $2"
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
if ! "$KERNEL_BUILDER_SCRIPT" $CONFIG_ARG $LOCALVERSION_ARG $THREADS_ARG; then
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
  [ -n "$LOCALVERSION_ARG" ] && DEPLOY_COMMAND+=" $LOCALVERSION_ARG"

  # Execute deployment command
  echo "Deploying compiled kernel to the Jetson device at $DEVICE_IP..."
  if ! eval $DEPLOY_COMMAND; then
    echo "Failed to deploy the compiled kernel to the Jetson device at $DEVICE_IP"
    exit 1
  fi
fi

echo "Kernel compilation and deployment (if applicable) completed successfully."

