#!/bin/bash

# Configuration
DEFAULT_INTERFACE="vcan0"
CAN_INTERFACE=$DEFAULT_INTERFACE
CAN_ID="123"                # Example CAN ID (Standard 11-bit)
PAYLOAD="DEADBEEF"          # The data payload
DEFAULT_RATE_HZ=100
RATE_HZ=$DEFAULT_RATE_HZ

# Default to CAN 2.0
MESSAGE_SEPARATOR="#"
CAN_PROTOCOL="CAN 2.0 (Standard)"

# CAN FD specific settings
CAN_FD_FLAG="1"             # Required CAN FD flags (e.g., '1' for BRS)

# --- Argument Parsing ---

# Read arguments until all are processed
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --freq)
            if [ -n "$2" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
                RATE_HZ="$2"
                shift
            else
                echo "Error: --freq requires a positive integer value." >&2
                exit 1
            fi
            ;;
        --interface)
            if [ -n "$2" ]; then
                CAN_INTERFACE="$2"
                shift
            else
                echo "Error: --interface requires a device name (e.g., vcan0, can0)." >&2
                exit 1
            fi
            ;;
        --fd)
            # Switch to CAN-FD mode
            MESSAGE_SEPARATOR="##$CAN_FD_FLAG"
            CAN_PROTOCOL="CAN-FD (Flags: $CAN_FD_FLAG)"
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
    shift
done

# --- Execution ---

# Check if the interface exists and is up
if ! ip link show "$CAN_INTERFACE" 2>/dev/null | grep -q "state UP"; then
    echo "ERROR: Interface '$CAN_INTERFACE' is not available or not UP." >&2
    echo "       Please ensure the interface is configured (e.g., 'sudo ip link set $CAN_INTERFACE up') before running." >&2
    exit 1
fi

if [ "$RATE_HZ" -le 0 ]; then
    echo "Error: Frequency must be a positive number." >&2
    exit 1
fi

# Calculate the sleep time in seconds (1 / RATE_HZ)
SLEEP_TIME=$(echo "scale=4; 1 / $RATE_HZ" | bc -l)

echo "--- CAN Sender Status ---"
echo "Interface: $CAN_INTERFACE"
echo "Protocol: $CAN_PROTOCOL"
echo "Sending ID: $CAN_ID, Payload: $PAYLOAD"
echo "Frequency: $RATE_HZ Hz (Sleep: $SLEEP_TIME seconds)"
echo "Press [CTRL+C] to stop."
echo "------------------------------"

while true; do
    # The message format is dynamically constructed using the separator:
    # <can_id> + <separator> + <payload>
    # e.g., "123#DEADBEEF" or "123##1DEADBEEF"
    cansend "$CAN_INTERFACE" "$CAN_ID$MESSAGE_SEPARATOR$PAYLOAD"

    # Wait for the calculated time
    sleep "$SLEEP_TIME"
done
