
#!/bin/bash

# Manage module-wide function filters for tracing
# Usage: ./manage_module_filters.sh <device-ip> <module-name> [--list | --add <function> | --remove <function>]

if [[ "$1" == "--help" ]]; then
  cat << EOF
Usage: ./manage_module_filters.sh <device-ip> <module-name> [--list | --add <function> | --remove <function>]

Description:
  This script dynamically lists all functions in a module and selectively adds or removes them from the trace filter.

Parameters:
  <device-ip>       IP address of the target device (e.g., Jetson Orin).
  <module-name>     Name of the kernel module to manage filters for.
  --list            Lists all functions available in the module.
  --add <function>  Adds a specific function to the trace filter.
  --remove <function> Removes a specific function from the trace filter.

Examples:
  List all functions in 'my_module':
    ./manage_module_filters.sh 192.168.1.100 my_module --list

  Add 'my_function' from 'my_module' to the filter:
    ./manage_module_filters.sh 192.168.1.100 my_module --add my_function

  Remove 'my_function' from the filter:
    ./manage_module_filters.sh 192.168.1.100 my_module --remove my_function
EOF
  exit 0
fi

DEVICE_IP="$1"
MODULE_NAME="$2"
ACTION="$3"
FUNCTION_NAME="$4"

TRACE_DIR="/sys/kernel/debug/tracing"
USERNAME="root"

if [ -z "$DEVICE_IP" ] || [ -z "$MODULE_NAME" ] || [ -z "$ACTION" ]; then
  echo "Usage: $0 <device-ip> <module-name> [--list | --add <function> | --remove <function>]"
  exit 1
fi

case "$ACTION" in
  --list)
    echo "Listing functions in module '$MODULE_NAME'..."
    ssh "$USERNAME@$DEVICE_IP" "cat /proc/kallsyms | grep '\sT\s' | grep '$MODULE_NAME'"
    ;;
  --add)
    if [ -z "$FUNCTION_NAME" ]; then
      echo "Error: Please specify a function to add."
      exit 1
    fi
    echo "Adding function '$FUNCTION_NAME' to the trace filter..."
    ssh "$USERNAME@$DEVICE_IP" "echo '$FUNCTION_NAME' > $TRACE_DIR/set_ftrace_filter"
    ;;
  --remove)
    if [ -z "$FUNCTION_NAME" ]; then
      echo "Error: Please specify a function to remove."
      exit 1
    fi
    echo "Removing function '$FUNCTION_NAME' from the trace filter..."
    ssh "$USERNAME@$DEVICE_IP" "sed -i '/^$FUNCTION_NAME\$/d' $TRACE_DIR/set_ftrace_filter"
    ;;
  *)
    echo "Invalid action: $ACTION. Use --list, --add, or --remove."
    exit 1
    ;;
esac
