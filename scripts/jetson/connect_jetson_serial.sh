#!/bin/bash

# Variables
SERIAL_BASE="/dev/serial/by-id"
BAUD_RATE=115200
SERIAL_DEVICE="usb-NVIDIA_Tegra_On-Platform_Operator_TOPO0C5FB339-if03"
SERIAL_PATH="$SERIAL_BASE/$SERIAL_DEVICE"

# Function to detect serial devices
list_serial_devices() {
    echo "🔍 Detecting devices in $SERIAL_BASE..."
    if [[ -d $SERIAL_BASE ]]; then
        ls -1 $SERIAL_BASE
    else
        echo "❌ No serial devices found."
        exit 1
    fi
}

# Function to troubleshoot devices
troubleshoot_serial_devices() {
    echo "🔧 Troubleshooting Mode"
    echo "-----------------------"
    echo "Testing serial devices in $SERIAL_BASE until a working connection is found..."

    if [[ ! -d $SERIAL_BASE ]]; then
        echo "❌ No serial devices found."
        exit 1
    fi

    for DEVICE in $SERIAL_BASE/*; do
        echo "Testing device: $DEVICE"
        echo "---------------------------------"
        echo "Attempting to open connection to $DEVICE..."
        echo "💡 If the connection works, you will stay in the console session."
        echo "💡 To exit manually, press: Ctrl-A followed by X."
        echo "💡 This test will automatically timeout after 10 seconds if no input is detected."

        # Attempt to connect using minicom with a timeout
        timeout 10 sudo minicom -D $DEVICE -b $BAUD_RATE
        if [[ $? -eq 0 ]]; then
            echo "✅ Successfully connected to $DEVICE."
            echo "Exiting troubleshooting mode."
            exit 0
        else
            echo "⚠️ Unable to connect to $DEVICE or timeout occurred. Trying the next device..."
        fi

        echo "---------------------------------"
    done

    echo "❌ No working serial connections found. Please check the device connections."
    exit 1
}


# Function to show help
show_help() {
    echo "Jetson Serial Connection Script"
    echo "--------------------------------"
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --help              Show this help message."
    echo "  --setup             Install required tools (minicom and screen)."
    echo "  --connect           Connect to the Jetson serial console."
    echo "  --troubleshoot      Test all available serial devices sequentially."
    echo
    echo "Default Behavior:"
    echo "  If no arguments are provided, the script will attempt to connect."
    echo
}

# Function to install required packages
setup_environment() {
    echo "🔧 Setting up environment..."
    if command -v apt >/dev/null; then
        sudo apt update
        sudo apt install -y minicom
    elif command -v pacman >/dev/null; then
        sudo pacman -Sy --noconfirm minicom
    else
        echo "❌ Unsupported system: could not detect a package manager."
        exit 1
    fi
    echo "✅ Setup complete."
}

# Function to connect to the Jetson
connect_to_jetson() {
    echo "Jetson Serial Connection"
    echo "-------------------------"
    echo "Using $SERIAL_PATH for serial communication."

    if [[ -e $SERIAL_PATH ]]; then
        echo "✅ Found device: $SERIAL_PATH"
        sudo minicom -D $SERIAL_PATH -b $BAUD_RATE
    else
        echo "❌ Device $SERIAL_PATH not found. Use --troubleshoot to test all devices."
        exit 1
    fi
}

# Parse arguments
if [[ $# -eq 0 ]]; then
    echo "ℹ️  No arguments provided. Defaulting to --connect."
    connect_to_jetson
else
    case "$1" in
        --help)
            show_help
            ;;
        --setup)
            setup_environment
            ;;
        --connect)
            connect_to_jetson
            ;;
        --troubleshoot)
            troubleshoot_serial_devices
            ;;
        *)
            echo "❌ Unknown option: $1. Use --help for usage information."
            exit 1
            ;;
    esac
fi

