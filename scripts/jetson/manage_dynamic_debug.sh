#!/bin/bash

# Correctly resolve SCRIPT_DIR one level up
SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

# Get the device IP
if [ -f "$SCRIPT_DIR/device_ip" ]; then
    DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip" | tr -d '\r')
else
    if [ "$#" -lt 1 ]; then
        echo "Usage: $0 [--help] <device-ip> --module <module-name> [--check-status | --enable | --disable | --toggle | --check-kernel-config]"
        exit 1
    fi
    DEVICE_IP=$1
    shift
fi

# Validate command-line arguments
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 [--help] <device-ip> --module <module-name> [--check-status | --enable | --disable | --toggle | --check-kernel-config]"
    exit 1
fi

# Parse arguments
ACTION=""
MODULE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --module)
            MODULE=$2
            shift 2
            ;;
        --check-status|--enable|--disable|--toggle|--check-kernel-config)
            ACTION=$1
            shift
            ;;
        --help)
            echo "Usage: $0 <device-ip> --module <module-name> [--check-status | --enable | --disable | --toggle | --check-kernel-config]"
            echo ""
            echo "Options:"
            echo "  --module <module-name>      Specify the module to target."
            echo "  --check-status              Check if debugging is enabled for the module."
            echo "  --enable                    Enable debugging for the module."
            echo "  --disable                   Disable debugging for the module."
            echo "  --toggle                    Toggle debugging for the module."
            echo "  --check-kernel-config       Verify if the kernel is configured for dynamic debugging."
            echo ""
            echo "Example:"
            echo "  $0 192.168.1.100 --module d4xx --check-status"
            echo "  $0 192.168.1.100 --check-kernel-config"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ "$ACTION" == "--check-kernel-config" ]]; then
    echo "Checking kernel configuration for dynamic debugging support on $DEVICE_IP..."

    REQUIRED_CONFIGS=("CONFIG_DYNAMIC_DEBUG" "CONFIG_DYNAMIC_DEBUG_CORE" "CONFIG_DEBUG_FS")
    MISSING_CONFIGS=()
    CONFIG_FILE="/proc/config.gz"

    if ! ssh root@"$DEVICE_IP" "test -f $CONFIG_FILE"; then
        echo "Error: Kernel config file not found at $CONFIG_FILE on the device."
        echo "If the file is missing, you may need to enable CONFIG_IKCONFIG and CONFIG_IKCONFIG_PROC in the kernel configuration."
        exit 1
    fi

    for CONFIG in "${REQUIRED_CONFIGS[@]}"; do
        echo "Checking $CONFIG..."
        RESULT=$(ssh root@"$DEVICE_IP" "zgrep -E '^$CONFIG=' $CONFIG_FILE || zgrep -E '^# $CONFIG is not set' $CONFIG_FILE")
        if [[ -z "$RESULT" || "$RESULT" == *"is not set"* ]]; then
            MISSING_CONFIGS+=("$CONFIG")
        fi
    done

    if [[ ${#MISSING_CONFIGS[@]} -gt 0 ]]; then
        echo "The following required kernel configurations are missing:"
        for CONFIG in "${MISSING_CONFIGS[@]}"; do
            echo "  - $CONFIG"
        done
        echo ""
        echo "To enable full dynamic debugging support, ensure CONFIG_DYNAMIC_DEBUG is set in your kernel configuration."
        echo "Rebuild your kernel with these options enabled and boot into the updated kernel."
        exit 1
    fi

    echo "All required kernel configurations are enabled."
    echo "If debugging for your module still isn't dynamic, check the Makefile."
    echo "For the d4xx module, ensure the following is included in your Makefile:"
    echo ""
    echo "    CFLAGS_d4xx.o := -DDEBUG"
    echo ""
    echo "This ensures dynamic debug macros like dev_dbg are compiled into your module."
    exit 0
fi

if [[ -z "$MODULE" ]] && [[ "$ACTION" != "--check-kernel-config" ]]; then
    echo "Error: --module is required."
    exit 1
fi

if [[ -z "$ACTION" ]]; then
    echo "Error: One of --check-status, --enable, --disable, --toggle, or --check-kernel-config is required."
    exit 1
fi

# Connect to the device and manage the module
DEBUG_FILE="/sys/kernel/debug/dynamic_debug/control"

ssh root@"$DEVICE_IP" "test -f $DEBUG_FILE"
if [[ $? -ne 0 ]]; then
    echo "Error: Debugging not available on the device."
    exit 1
fi

case "$ACTION" in
    --check-status)
        STATUS=$(ssh root@"$DEVICE_IP" "grep '$MODULE' $DEBUG_FILE | grep '+p'")
        if [[ -z "$STATUS" ]]; then
            echo "Debugging is currently DISABLED for module: $MODULE."
        else
            echo "Debugging is currently ENABLED for module: $MODULE."
        fi
        ;;
    --enable)
        ssh root@"$DEVICE_IP" "echo 'module $MODULE +p' > $DEBUG_FILE"
        echo "Debugging enabled for module: $MODULE"
        ;;
    --disable)
        ssh root@"$DEVICE_IP" "echo 'module $MODULE -p' > $DEBUG_FILE"
        echo "Debugging disabled for module: $MODULE"
        ;;
    --toggle)
        STATUS=$(ssh root@"$DEVICE_IP" "grep '$MODULE' $DEBUG_FILE | grep '+p'")
        if [[ -n "$STATUS" ]]; then
            ssh root@"$DEVICE_IP" "echo 'module $MODULE -p' > $DEBUG_FILE"
            echo "Debugging disabled for module: $MODULE"
        else
            ssh root@"$DEVICE_IP" "echo 'module $MODULE +p' > $DEBUG_FILE"
            echo "Debugging enabled for module: $MODULE"
        fi
        ;;
    *)
        echo "Unknown action: $ACTION"
        exit 1
        ;;
esac

