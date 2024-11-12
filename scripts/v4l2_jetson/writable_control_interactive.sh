#!/bin/bash

# Display help information
if [[ "$1" == "--help" ]]; then
  echo "writable_control_interactive.sh - Interactively modify writable controls for video devices on a target device or the host."
  echo
  echo "Usage:"
  echo "  $0 [--host] [<device-ip>] [<username>]"
  echo
  echo "Description:"
  echo "  Lists all video devices and their writable controls either on the specified target device"
  echo "  via SSH or on the host if --host is used. Allows the user to select a control to modify"
  echo "  and specify a new value."
  echo
  echo "Examples:"
  echo "  $0 --host"
  echo "  $0 192.168.1.100 root"
  exit 0
fi

# Check if targeting host or remote device
if [[ "$1" == "--host" ]]; then
  TARGET_HOST="localhost"
else
  # Set the script directory and device IP
  SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"

  # Check if device_ip file exists
  if [ -f "$SCRIPT_DIR/device_ip" ]; then
    DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
  else
    if [ "$#" -lt 1 ]; then
      echo "Usage: $0 [--host] [<device-ip>] [<username>]"
      exit 1
    fi
    DEVICE_IP=$1
  fi

  # Default to username "root" if not specified
  USERNAME=${2:-root}
  TARGET_HOST="$USERNAME@$DEVICE_IP"
fi

# Function to execute commands on target (locally or via SSH)
execute_on_target() {
  if [[ "$TARGET_HOST" == "localhost" ]]; then
    eval "$1"
  else
    ssh "$TARGET_HOST" "$1"
  fi
}

# List all video devices on the target
VIDEO_DEVICES=$(execute_on_target "ls /dev/video* 2>/dev/null")
if [ -z "$VIDEO_DEVICES" ]; then
  echo "No video devices found on the target device."
  exit 1
fi

# Define dependency controls that require disabling automatic settings to become writable
declare -A dependency_controls=(
  ["auto_exposure"]="exposure_time_absolute"
  ["white_balance_automatic"]="white_balance_temperature"
  ["focus_auto"]="focus_absolute"
  ["gain_automatic"]="gain"
  ["exposure_auto"]="exposure_absolute"
)

# For each video device, list controls and categorize them as writable, inactive, or dependent on automatic settings
declare -A controls
for DEVICE in $VIDEO_DEVICES; do
  echo "Checking controls for $DEVICE..."

  v4l2_output=$(execute_on_target "v4l2-ctl -d '$DEVICE' --list-ctrls-menus")

  # Parse control information
  echo "$v4l2_output" | while read -r line; do
    # Extract control details
    control_name=$(echo "$line" | awk '{print $1}')
    value=$(echo "$line" | grep -o 'value=[0-9]*' | cut -d= -f2)
    min=$(echo "$line" | grep -o 'min=[0-9]*' | cut -d= -f2)
    max=$(echo "$line" | grep -o 'max=[0-9]*' | cut -d= -f2)
    flags=$(echo "$line" | grep -o 'flags=[a-zA-Z]*')

    # Check if the control is writable, inactive, or dependent on automatic settings
    if [[ "$flags" == "inactive" ]]; then
      echo "Inactive control found: $control_name (value=$value, range=$min-$max)"
      # Check if this control is dependent on an automatic setting
      for auto_control in "${!dependency_controls[@]}"; do
        if [[ "${dependency_controls[$auto_control]}" == "$control_name" ]]; then
          echo "To make $control_name writable, disable $auto_control."
          read -p "Would you like to disable $auto_control to make $control_name writable? (y/n): " choice
          if [[ "$choice" == "y" ]]; then
            execute_on_target "v4l2-ctl -d '$DEVICE' --set-ctrl=$auto_control=0" # Manual Mode
            echo "$auto_control set to manual mode."
          fi
        fi
      done
    elif [[ "$line" == *"writable"* ]]; then
      echo "Writable control found: $control_name (value=$value, range=$min-$max)"
      controls["$DEVICE,$control_name"]="$value,$min,$max"
    else
      echo "Non-writable control found: $control_name"
    fi
  done
done

# Display all writable controls and prompt user to select one
echo "Writable controls found:"
i=1
control_list=()
for key in "${!controls[@]}"; do
  dev=$(echo "$key" | cut -d, -f1)
  name=$(echo "$key" | cut -d, -f2)
  value=$(echo "${controls[$key]}" | cut -d, -f1)
  min=$(echo "${controls[$key]}" | cut -d, -f2)
  max=$(echo "${controls[$key]}" | cut -d, -f3)

  echo "$i) Device: $dev, Control: $name, Current: $value, Range: min=$min max=$max"
  control_list+=("$key")
  ((i++))
done

if [ "${#control_list[@]}" -eq 0 ]; then
  echo "No writable controls found."
  exit 0
fi

read -p "Select a control to modify (1-${#control_list[@]}): " choice
if (( choice < 1 || choice > ${#control_list[@]} )); then
  echo "Invalid choice."
  exit 1
fi

# Get selected control details
selected_key="${control_list[choice-1]}"
selected_dev=$(echo "$selected_key" | cut -d, -f1)
selected_control=$(echo "$selected_key" | cut -d, -f2)
current_value=$(echo "${controls[$selected_key]}" | cut -d, -f1)
min_value=$(echo "${controls[$selected_key]}" | cut -d, -f2)
max_value=$(echo "${controls[$selected_key]}" | cut -d, -f3)

echo "Selected control:"
echo "Device: $selected_dev"
echo "Control: $selected_control"
echo "Current Value: $current_value"
echo "Range: min=$min_value, max=$max_value"

# Prompt user for new value
read -p "Enter a new value for $selected_control (between $min_value and $max_value): " new_value

# Validate the new value
if (( new_value < min_value || new_value > max_value )); then
  echo "Error: Value out of range."
  exit 1
fi

# Set the new value
execute_on_target "v4l2-ctl -d '$selected_dev' --set-ctrl=$selected_control=$new_value" && \
echo "Successfully set $selected_control to $new_value on $selected_dev."

