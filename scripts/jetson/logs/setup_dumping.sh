#!/bin/bash

# Variables
SCRIPT_DIR="$(realpath "$(dirname "$0")/../..")"
KDUMP_DIR="/xavier_ssd/data/kdump"
KERNEL_IMAGE="/boot/Image"

echo "$SCRIPT_DIR"

# Usage Information
if [ "$#" -gt 2 ]; then
  echo "Usage: $0 [<device-ip>] [<username>]"
  exit 1
fi

# Get the target device IP address
if [ -f "$SCRIPT_DIR/device_ip" ]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/device_ip")
else
  if [ "$#" -ge 1 ]; then
    DEVICE_IP=$1
  else
    echo "Device IP not provided. Please provide as argument or create device_ip file."
    exit 1
  fi
fi

# Get the target device username
if [ -f "$SCRIPT_DIR/device_username" ]; then
  USERNAME=$(cat "$SCRIPT_DIR/device_username")
else
  if [ "$#" -eq 2 ]; then
    USERNAME=$2
  else
    USERNAME="cartken"  # Default username if not provided
  fi
fi

echo "Connecting to $DEVICE_IP as $USERNAME..."

# Step 1: Create kdump directory on the target device
echo "Creating kdump directory at $KDUMP_DIR..."
ssh "$USERNAME@$DEVICE_IP" "sudo mkdir -p $KDUMP_DIR && sudo chmod 755 $KDUMP_DIR"

# Step 2: Configure kernel dump settings and enable earlyprintk
echo "Configuring kernel dump settings..."
ssh "$USERNAME@$DEVICE_IP" "sudo apt-get update"
ssh "$USERNAME@$DEVICE_IP" "sudo apt-get install -y kexec-tools"

echo "Updating /boot/extlinux/extlinux.conf to add crashkernel parameter..."
ssh "$USERNAME@$DEVICE_IP" "if ! grep -q 'crashkernel=' /boot/extlinux/extlinux.conf; then sudo sed -i 's|/boot/Image|/boot/Image crashkernel=128M|' /boot/extlinux/extlinux.conf; fi"

echo "Setting kexec to use crashkernel parameter..."
ssh "$USERNAME@$DEVICE_IP" "if ! grep -q 'crashkernel=128M' /proc/cmdline; then sudo kexec -p '$KERNEL_IMAGE' --append='crashkernel=128M root=$(awk '\$2 == \"/\" {print \$1}' /etc/fstab) rd.lvm=1 rd.md=0 rd.dm=0'; fi"

echo "Enabling earlyprintk for kernel..."
ssh "$USERNAME@$DEVICE_IP" "if ! grep -q 'earlyprintk' /boot/extlinux/extlinux.conf; then sudo sed -i 's|/boot/Image|& earlyprintk=serial,ttyS0,115200|' /boot/extlinux/extlinux.conf; fi"

# Step 3: Persistent dmesg logging and trace-cmd setup
echo "Setting up persistent dmesg logging..."
ssh "$USERNAME@$DEVICE_IP" "
  sudo mkdir -p /var/log/dmesg
  if ! grep -q '/var/log/dmesg' /etc/rsyslog.d/50-default.conf; then
    echo '/var/log/dmesg' | sudo tee -a /etc/rsyslog.d/50-default.conf
  else
    echo '/var/log/dmesg is already configured in 50-default.conf, skipping this step.'
  fi
"

echo "Installing trace-cmd..."
ssh "$USERNAME@$DEVICE_IP" "sudo apt-get install -y trace-cmd"

echo "Creating directory for trace logs..."
ssh "$USERNAME@$DEVICE_IP" "sudo mkdir -p $KDUMP_DIR/trace_logs"

echo "Starting trace-cmd to capture kernel events..."
ssh "$USERNAME@$DEVICE_IP" "sudo trace-cmd record -D -o $KDUMP_DIR/trace_logs/trace.dat"

echo "Ensuring trace-cmd starts on reboot..."
ssh "$USERNAME@$DEVICE_IP" "echo '@reboot sudo trace-cmd record -D -o $KDUMP_DIR/trace_logs/trace.dat' | sudo tee -a /etc/crontab"

echo "Configuration complete. Reboot your device to apply changes."

