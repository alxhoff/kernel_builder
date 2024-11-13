#!/bin/bash

# build_and_deploy_targeted_modules.sh
# Master script to build and deploy targeted modules for a Jetson device
# Usage: ./build_and_deploy_targeted_modules.sh [--no-deploy] [--config <config-file>] [--localversion <version>] [--dry-run] [--threads <number>] [--host-build]
# Arguments:
#   --no-deploy     Optional argument to skip deploying the kernel to the device
#   --config        Optional argument to specify the kernel configuration file to use
#   --localversion  Optional argument to set a custom local version string during kernel compilation
#   --dry-run       Optional argument to simulate the deployment process without copying anything to the Jetson device
#   --threads       Optional argument to specify the number of threads to use during kernel compilation
#   --host-build    Optional argument to perform the build on the host machine instead of using Docker

if [[ "$1" == "--help" ]]; then
  echo "Usage: ./build_and_deploy_targeted_modules.sh [OPTIONS]"
  echo ""
  echo "Master script to build and deploy targeted kernel modules for a Jetson device. The modules to be built or deployed must be specified in a file called 'target_modules.txt', which should be located in the same directory as this script."
  echo ""
  echo "Options:"
  echo "  --no-deploy              Skip deploying the kernel to the Jetson device after building."
  echo "  --config <config-file>   Specify the kernel configuration file to use during the build."
  echo "  --localversion <version> Set a custom local version string during kernel compilation."
  echo "  --dry-run                Simulate the deployment process without actually transferring files."
  echo "  --threads <number>       Specify the number of threads to use during kernel compilation."
  echo "  --host-build             Perform the build on the host machine instead of using Docker."
  echo "  --help                   Show this help message and exit."
  echo ""
  echo "Examples:"
  echo "  ./build_and_deploy_targeted_modules.sh --config defconfig --localversion custom_version --threads 8"
  echo "  ./build_and_deploy_targeted_modules.sh --no-deploy --host-build"
  echo ""
  echo "Note: The list of target modules must be specified in the 'target_modules.txt' file."
  exit 0
fi

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
BUILD_SCRIPT="$SCRIPT_DIR/build_targeted_modules.sh"
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy_targeted_modules.sh"

# Check arguments
NO_DEPLOY=false
CONFIG_ARG=""
LOCALVERSION_ARG=""
DRY_RUN=false
THREADS_ARG=""
HOST_BUILD=false

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

# Run the build script
BUILD_COMMAND="$BUILD_SCRIPT $CONFIG_ARG --localversion $LOCALVERSION_ARG $THREADS_ARG"
[ "$HOST_BUILD" == true ] && BUILD_COMMAND+=" --host-build"

echo "Running build script: $BUILD_COMMAND"
eval $BUILD_COMMAND

# Run the deploy script (if not skipped)
if [ "$NO_DEPLOY" == false ]; then
  DEPLOY_COMMAND="$DEPLOY_SCRIPT --ip ${DEVICE_IP} --user ${USERNAME}"
  [ -n "$LOCALVERSION_ARG" ] && DEPLOY_COMMAND+=" --localversion ${LOCALVERSION_ARG#--localversion }"
  [ "$DRY_RUN" == true ] && DEPLOY_COMMAND+=" --dry-run"

  echo "Running deploy script: $DEPLOY_COMMAND"
  eval $DEPLOY_COMMAND
fi

echo "Build and deploy (if applicable) completed successfully."

