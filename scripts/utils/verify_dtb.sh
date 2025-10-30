#!/bin/bash

# --- Default Configuration ---
DEFAULT_USER="cartken"
# -----------------------------

TARGET_IP=""
OUTPUT_FILE=""
JETSON_USER=$DEFAULT_USER

# --- Helper function for usage ---
show_usage() {
    echo "Usage: $0 --ip <target-ip> [--output-file <filename.dts>] [--user <username>]"
    echo ""
    echo "  --ip <target-ip>     (Required) The IP address of the target Jetson machine."
    echo "  --output-file <file> (Optional) The name of the decompiled .dts file to create."
    echo "  --user <username>    (Optional) The SSH user for the Jetson (default: '$DEFAULT_USER')."
    echo ""
    echo "  To run without password prompts, first install 'sshpass' (sudo apt install sshpass)"
    echo "  Then run: SSHPASS='your_pass' $0 --ip <ip>"
    exit 1
}

# --- Parse Command-Line Arguments ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --ip)
            TARGET_IP="$2"
            shift
            ;;
        --output-file)
            OUTPUT_FILE="$2"
            shift
            ;;
        --user)
            JETSON_USER="$2"
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo "Error: Unknown parameter passed: $1"
            show_usage
            ;;
    esac
    shift
done

# --- Validate Inputs ---
if [ -z "$TARGET_IP" ]; then
    echo "Error: --ip argument is required."
    echo ""
    show_usage
fi

if ! command -v dtc &> /dev/null; then
    echo "Error: 'dtc' (Device Tree Compiler) is not found on your *local* machine."
    echo "Please install it (e.g., sudo apt install device-tree-compiler)"
    exit 1
fi

# --- NEW: Check for sshpass and SSHPASS variable ---
SSH_PREFIX=""
if [ -n "$SSHPASS" ]; then
    if command -v sshpass &> /dev/null; then
        echo "🔑 'SSHPASS' variable detected. Using 'sshpass' to automate login."
        SSH_PREFIX="sshpass -e"
    else
        echo "⚠️ 'SSHPASS' variable is set, but 'sshpass' is not installed."
        echo "   Please run: sudo apt install sshpass"
        echo "   Will proceed with manual password prompts..."
    fi
fi
# --- End of new section ---


# --- Set Default Output Filename ---
if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="${TARGET_IP}_running_proc.dts"
fi

# --- Define File Paths (now using $SSH_PREFIX) ---
SSH_CMD="$SSH_PREFIX ssh ${JETSON_USER}@${TARGET_IP}"
SCP_CMD="$SSH_PREFIX scp -r" # Use recursive scp
TEMP_DT_DIR_HOST="temp_dt_dir_${TARGET_IP}" # Temp directory on host


# --- Main Logic ---

# Clean up previous temporary directory if it exists
if [ -d "$TEMP_DT_DIR_HOST" ]; then
    echo "🧹 Cleaning up old temporary directory '$TEMP_DT_DIR_HOST'..."
    rm -rf "$TEMP_DT_DIR_HOST"
fi

echo "➡️ STEP 1: Copying /proc/device-tree from target ${JETSON_USER}@${TARGET_IP}..."
# Use scp to recursively copy the directory. Redirect output to /dev/null for cleaner execution.
$SCP_CMD "${JETSON_USER}@${TARGET_IP}:/proc/device-tree" "$TEMP_DT_DIR_HOST" >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to copy /proc/device-tree from the target machine."
    echo "   Please check your SSH connection and permissions."
    exit 1
fi

echo "⬇️  STEP 2: Decompiling '$TEMP_DT_DIR_HOST' to '$OUTPUT_FILE' on host..."
# Now use dtc on the host, reading from the copied directory
dtc -I fs -O dts -o "$OUTPUT_FILE" "$TEMP_DT_DIR_HOST"

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to decompile '$TEMP_DT_DIR_HOST' with 'dtc'."
    rm -rf "$TEMP_DT_DIR_HOST" # Clean up
    exit 1
fi

echo "🧹 STEP 3: Cleaning up local temporary directory..."
rm -rf "$TEMP_DT_DIR_HOST"

echo "---"
echo "✅ Success! Live device tree from $TARGET_IP has been saved to: $OUTPUT_FILE"
