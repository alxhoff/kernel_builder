#!/bin/bash

# Variables
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
KDUMP_DIR="/xavier_ssd/data/kdump"
KERNEL_IMAGE="/boot/Image"

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

# Step 2: Configure kdump to save dumps to this folder
echo "Configuring kernel dump settings..."
ssh "$USERNAME@$DEVICE_IP" << 'EOF'
sudo apt-get update
sudo apt-get install -y kexec-tools

# Set up kexec with crashkernel and specify the dump location
if ! grep -q "crashkernel=" /boot/extlinux/extlinux.conf; then
    sudo sed -i 's|/boot/Image|/boot/Image crashkernel=128M|' /boot/extlinux/extlinux.conf
fi

# Update kernel command line for kdump and earlyprintk
if ! grep -q "crashkernel=128M" /proc/cmdline; then
    sudo kexec -p "$KERNEL_IMAGE" --append="crashkernel=128M root=$(awk '$2 == "/" {print $1}' /etc/fstab) rd.lvm=1 rd.md=0 rd.dm=0"
fi

# Enable earlyprintk
if ! grep -q "earlyprintk" /boot/extlinux/extlinux.conf; then
    sudo sed -i 's|/boot/Image|& earlyprintk=serial,ttyS0,115200|' /boot/extlinux/extlinux.conf
fi
EOF

# Step 3: Persistent dmesg logging and trace-cmd setup
echo "Setting up persistent dmesg logging and trace-cmd capture..."

ssh "$USERNAME@$DEVICE_IP" << 'EOF'
# Install necessary tools
sudo apt-get install -y trace-cmd

# Enable persistent dmesg logging
sudo mkdir -p /var/log/dmesg
echo '/var/log/dmesg' | sudo tee -a /etc/rsyslog.d/50-default.conf

# Set up trace-cmd to log kernel events to persistent storage
TRACE_DIR="$KDUMP_DIR/trace_logs"
sudo mkdir -p $TRACE_DIR
sudo trace-cmd record -D -o $TRACE_DIR/trace.dat

# Ensure logs are saved even after reboot
echo "@reboot sudo trace-cmd record -D -o $TRACE_DIR/trace.dat" | sudo tee -a /etc/crontab
EOF

echo "Configuration complete. Reboot your device to apply changes."

