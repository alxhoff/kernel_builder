#!/usr/bin/env bash
set -euo pipefail

# --- Check for sudo/root ---
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root. Use: sudo $0"
    exit 1
fi

# --- Prompt for identifiers ---
read -rp "Enter your name (no spaces), e.g. alex_hoff: " USER_NAME
read -rp "Enter the laptop/PC model (no spaces), e.g. x13_thinkpad: " MACHINE_MODEL

BASENAME="flash_host_${USER_NAME}_${MACHINE_MODEL}"
SYSINFO_LOG="${BASENAME}_system_info.txt"
USBINFO_LOG="${BASENAME}_usb_info.txt"

# --- System Info Dump ---
echo "[*] Collecting full system info into $SYSINFO_LOG..."
{
    echo "=== uname ==="
    uname -a

    echo -e "\n=== OS Version ==="
    lsb_release -a 2>/dev/null || cat /etc/os-release

    echo -e "\n=== Entered Machine Model ==="
    echo "Model ID: ${MACHINE_MODEL}"

    if command -v dmidecode &>/dev/null; then
        echo -e "\n=== dmidecode System Info ==="
        echo -n "Manufacturer: "; dmidecode -s system-manufacturer
        echo -n "Product Name: "; dmidecode -s system-product-name
        echo -n "Serial Number: "; dmidecode -s system-serial-number
    fi

    echo -e "\n=== CPU Info ==="
    lscpu

    echo -e "\n=== Memory Info ==="
    free -h

    echo -e "\n=== PCI Devices ==="
    lspci -nn

    echo -e "\n=== Loaded Kernel Modules ==="
    lsmod

    echo -e "\n=== Kernel Command Line ==="
    cat /proc/cmdline

    echo -e "\n=== Environment ==="
    env
} > "$SYSINFO_LOG"

# --- USB Hardware Info Dump ---
echo "[*] Collecting USB-specific info into $USBINFO_LOG..."
{
    echo "=== USB Hub Summary (Class=Hub) ==="
    USB_IDS="/usr/share/misc/usb.ids"
    CURRENT_ID=""
    BUS=""
    DEV=""
    IS_HUB=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^Bus\ ([0-9]+)\ Device\ ([0-9]+):\ ID\ ([0-9a-f]{4}):([0-9a-f]{4}) ]]; then
            BUS="${BASH_REMATCH[1]}"
            DEV="${BASH_REMATCH[2]}"
            VID="${BASH_REMATCH[3]}"
            PID="${BASH_REMATCH[4]}"
            CURRENT_ID="${VID}:${PID}"
            IS_HUB=0
        elif [[ "$line" =~ bDeviceClass[[:space:]]+9 ]]; then
            IS_HUB=1
        elif [[ -z "$line" && "$IS_HUB" == "1" ]]; then
            {
                VENDOR_LINE=$(grep -i "^$VID[[:space:]]" "$USB_IDS" | head -n1 || true)
                PRODUCT_LINE=$(grep -A20 -i "^$VID[[:space:]]" "$USB_IDS" | grep -i "^[[:space:]]\+$PID[[:space:]]" | head -n1 || true)
                VENDOR_NAME=$(echo "$VENDOR_LINE" | cut -d' ' -f2- || true)
                PRODUCT_NAME=$(echo "$PRODUCT_LINE" | sed 's/^[ \t]*[0-9a-f]\{4\}[ \t]*//' || true)
                DESC="${VENDOR_NAME} ${PRODUCT_NAME}"
                [[ -z "$DESC" || "$DESC" = " " ]] && DESC="Unknown"
                echo "$BUS:$DEV (${CURRENT_ID}) -> $DESC [VID=${VID} PID=${PID}]"
            } || true
            IS_HUB=0
        fi
    done < <(lsusb -v 2>/dev/null)

    echo -e "\n=== USB Tree Topology (lsusb -t) ==="
    lsusb -t

    echo -e "\n=== USB Devices (usb-devices) ==="
    usb-devices

    echo -e "\n=== USB Host Controllers (lspci -nn | grep -i usb) ==="
    lspci -nn | grep -i usb

    echo -e "\n=== Kernel Modules for USB ==="
    lsmod | grep -i usb

    echo -e "\n=== USB Hardware (lshw -class usb) ==="
    if command -v lshw >/dev/null; then
        lshw -class usb
    else
        echo "lshw not installed."
    fi

    echo -e "\n=== USB Devices via /sys/bus/usb/devices ==="
    for d in /sys/bus/usb/devices/*; do
        if [[ -f "$d/product" ]]; then
            echo -n "$d: "
            cat "$d/manufacturer" 2>/dev/null || echo -n ""
            echo -n " "
            cat "$d/product" 2>/dev/null
        fi
    done

    echo -e "\n=== Full lsusb -v ==="
    lsusb -v 2>/dev/null

} >> "$USBINFO_LOG"

# --- Done ---
echo "[+] Logs saved as:"
echo "    $SYSINFO_LOG"
echo "    $USBINFO_LOG"

