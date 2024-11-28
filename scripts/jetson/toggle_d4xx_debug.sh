#!/bin/bash

# Get the directory of this script
SCRIPT_DIR="$(realpath "$(dirname "$0")")"

# Define the module name
MODULE="d4xx"

# Check the current debugging status
echo "Checking current debugging status for module: $MODULE..."
CURRENT_STATUS=$("$SCRIPT_DIR/manage_dynamic_debug.sh" "$@" --module "$MODULE" --check-status)

# Parse the output to determine the current state
if echo "$CURRENT_STATUS" | grep -q "DISABLED"; then
    echo "Debugging is currently DISABLED for module: $MODULE."
    PROMPT_TOGGLE="enable"
else
    echo "Debugging is currently ENABLED for module: $MODULE."
    PROMPT_TOGGLE="disable"
fi

# Prompt the user to toggle
read -p "Do you want to $PROMPT_TOGGLE debugging for $MODULE? [Y/n]: " RESPONSE
RESPONSE=${RESPONSE:-Y} # Default to "yes" if no input is provided

if [[ "$RESPONSE" =~ ^[Yy]$ ]]; then
    echo "Toggling debugging state for $MODULE..."
    "$SCRIPT_DIR/manage_dynamic_debug.sh" "$@" --module "$MODULE" --toggle
else
    echo "No changes made."
fi

