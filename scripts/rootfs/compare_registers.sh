#!/bin/bash

# Script to compare register values between two devices via SSH.
# It takes two IP addresses as arguments.

# --- Configuration ---
# List of memory addresses to check
ADDRESSES=("0x0243d020" "0x0c303040" "0x0c302048" "0x0c302070" "0x02430080" "0x02430090" "0x0243d028" "0x0243d018" "0x0243d040" "0x0243d008" "0x0243d038")
NAMES=("SW-CS0-Pin22" "SW-CS1-Pin32" "IRQ2-Pin16" "IRQ0-Pin7" "IRQ1-Pin13" "IRQ3-Pin36" "SPI1-SCK-Pin23" "SPI1-MISO-Pin21" "SPI1-MOSI-Pin19" "SPI1-CS0-Pin24" "SPI1-CS1-Pin26")

# SSH user
SSH_USER="root"

# --- Script Logic ---
# Check for correct number of arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <ip1> <ip2>"
    echo "Compares a predefined list of memory registers between two devices."
    exit 1
fi

IP1=$1
IP2=$2

echo "Comparing register values between $IP1 and $IP2"

printf "%-20s | %-12s | %-18s | %-18s | %-11s | %s
" "Name" "Register" "$IP1" "$IP2" "Full Match" "Partial Match (LSB)"
echo "----------------------------------------------------------------------------------------------------------------"

# Loop through each address and compare
for i in "${!ADDRESSES[@]}"; do
    ADDR=${ADDRESSES[$i]}
    NAME=${NAMES[$i]}
    # Fetch value from the first device
    VAL1=$(ssh "${SSH_USER}@${IP1}" "busybox devmem ${ADDR}" 2>/dev/null)
    # Fetch value from the second device
    VAL2=$(ssh "${SSH_USER}@${IP2}" "busybox devmem ${ADDR}" 2>/dev/null)

    # Clean up potential carriage returns or extra whitespace from ssh
    VAL1_CLEAN=$(echo "$VAL1" | tr -d '\r' | xargs)
    VAL2_CLEAN=$(echo "$VAL2" | tr -d '\r' | xargs)

    # Check if commands were successful
    if [ -z "$VAL1_CLEAN" ]; then
        echo "Error fetching value for $ADDR from $IP1"
        continue
    fi
    if [ -z "$VAL2_CLEAN" ]; then
        echo "Error fetching value for $ADDR from $IP2"
        continue
    fi

    # Full comparison
    if [ "$VAL1_CLEAN" == "$VAL2_CLEAN" ]; then
        FULL_RESULT="Same"
    else
        FULL_RESULT="Different"
    fi

    # Partial comparison (last 8 chars)
    PARTIAL_VAL1=${VAL1_CLEAN: -8}
    PARTIAL_VAL2=${VAL2_CLEAN: -8}

    if [ "$PARTIAL_VAL1" == "$PARTIAL_VAL2" ]; then
        PARTIAL_RESULT="Same"
    else
        PARTIAL_RESULT="Different"
    fi

    # Print the results
    printf "%-20s | %-12s | %-18s | %-18s | %-11s | %s
" "$NAME" "$ADDR" "$VAL1_CLEAN" "$VAL2_CLEAN" "$FULL_RESULT" "$PARTIAL_RESULT"

done

echo "----------------------------------------------------------------------------------------------------------------"
echo "Comparison finished."
