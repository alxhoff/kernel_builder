#!/bin/bash

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Constants
IMAGE_FOLDER="Cartken_Jetson_Image_35.4.1-standalone-20240516-1"
L4T_FOLDER="Linux_for_Tegra"

# Step 1: User specifies the tar file location
echo "Step 1: Specify the location of the tar file"
read -p "Enter the full path to the tar file (e.g., /path/to/Cartken_Jetson_Image.tar.gz): " IMAGE_SOURCE

if [ ! -f "$IMAGE_SOURCE" ]; then
  echo "File not found: $IMAGE_SOURCE"
  exit 1
fi

# Step 2: Select USB drive using improved selection logic
echo "Step 2: Select USB drive"
echo "Available unmounted disks:"
DISKS=($(lsblk -dno NAME | while read -r disk; do
    mountpoint=$(lsblk -nro MOUNTPOINT "/dev/$disk" | grep -v "^$")
    if [ -z "$mountpoint" ]; then
        echo "$disk"
    fi
done))

if [ ${#DISKS[@]} -eq 0 ]; then
  echo "No unmounted disks available."
  exit 1
fi

for i in "${!DISKS[@]}"; do
  echo "$((i + 1)): /dev/${DISKS[i]}"
done

# Prompt user to select a disk by index
read -p "Enter the number of the disk to use as the USB drive: " DISK_INDEX
DISK_INDEX=$((DISK_INDEX - 1))

if [ -z "${DISKS[$DISK_INDEX]}" ]; then
  echo "Invalid selection."
  exit 1
fi

USB_PATH="/dev/${DISKS[$DISK_INDEX]}"
echo "Selected disk: $USB_PATH"

# Step 3: Extract the image source
echo "Step 3: Extracting image source..."
sudo tar xvpf "$IMAGE_SOURCE" || { echo "Extraction failed"; exit 1; }

# Navigate to Linux_for_Tegra folder
cd "$IMAGE_FOLDER/$L4T_FOLDER" || { echo "Failed to navigate to $L4T_FOLDER"; exit 1; }

# Step 4: Create XML partition configuration files
echo "Step 4: Creating XML partition configuration files"

PARTITION_FILE_3_PART="tools/kernel_flash/flash_l4t_external_3_part.xml"
PARTITION_FILE_1_PART="tools/kernel_flash/flash_l4t_external_1_part.xml"

# 3-Partition Configuration
sudo tee "$PARTITION_FILE_3_PART" > /dev/null <<EOF
<partition_layout version="01.00.0000">
    <device type="external" instance="0" sector_size="512" num_sectors="NUM_SECTORS">
        <partition name="master_boot_record" type="protective_master_boot_record">
            <allocation_policy> sequential </allocation_policy>
            <filesystem_type> basic </filesystem_type>
            <size> 512 </size>
            <file_system_attribute> 0 </file_system_attribute>
            <allocation_attribute> 8 </allocation_attribute>
            <percent_reserved> 0 </percent_reserved>
            <description> **Required.** Contains protective MBR. </description>
        </partition>
        <partition name="primary_gpt" type="primary_gpt">
            <allocation_policy> sequential </allocation_policy>
            <filesystem_type> basic </filesystem_type>
            <size> 19968 </size>
            <file_system_attribute> 0 </file_system_attribute>
            <allocation_attribute> 8 </allocation_attribute>
            <percent_reserved> 0 </percent_reserved>
            <description> **Required.** Contains primary GPT of the external device. </description>
        </partition>
        <partition name="APP" type="data">
            <allocation_policy> sequential </allocation_policy>
            <filesystem_type> basic </filesystem_type>
            <size> APPSIZE </size>
            <file_system_attribute> 0 </file_system_attribute>
            <allocation_attribute> 0x8 </allocation_attribute>
            <align_boundary> 4096 </align_boundary>
            <percent_reserved> 0 </percent_reserved>
            <filename> APPFILE </filename>
            <unique_guid> APPUUID </unique_guid>
            <description> Contains the root filesystem with kernel and initrd in /boot. </description>
        </partition>
        <partition name="secondary_gpt" type="secondary_gpt">
            <allocation_policy> sequential </allocation_policy>
            <filesystem_type> basic </filesystem_type>
            <size> 0xFFFFFFFFFFFFFFFF </size>
            <file_system_attribute> 0 </file_system_attribute>
            <allocation_attribute> 8 </allocation_attribute>
            <percent_reserved> 0 </percent_reserved>
            <description> **Required.** Contains secondary GPT of the external device. </description>
        </partition>
    </device>
</partition_layout>
EOF

# 1-Partition Configuration
sudo tee "$PARTITION_FILE_1_PART" > /dev/null <<EOF
<partition_layout version="01.00.0000">
    <device type="external" instance="0" sector_size="512" num_sectors="NUM_SECTORS">
        <partition name="master_boot_record" type="protective_master_boot_record">
            <allocation_policy> sequential </allocation_policy>
            <filesystem_type> basic </filesystem_type>
            <size> 512 </size>
            <file_system_attribute> 0 </file_system_attribute>
            <allocation_attribute> 8 </allocation_attribute>
            <percent_reserved> 0 </percent_reserved>
            <description> **Required.** Contains protective MBR. </description>
        </partition>
        <partition name="primary_gpt" type="primary_gpt">
            <allocation_policy> sequential </allocation_policy>
            <filesystem_type> basic </filesystem_type>
            <size> 19968 </size>
            <file_system_attribute> 0 </file_system_attribute>
            <allocation_attribute> 8 </allocation_attribute>
            <percent_reserved> 0 </percent_reserved>
            <description> **Required.** Contains primary GPT of the external device. </description>
        </partition>
        <partition name="APP" type="data">
            <allocation_policy> sequential </allocation_policy>
            <filesystem_type> basic </filesystem_type>
            <size> APPSIZE </size>
            <file_system_attribute> 0 </file_system_attribute>
            <allocation_attribute> 0x8 </allocation_attribute>
            <align_boundary> 4096 </align_boundary>
            <percent_reserved> 0 </percent_reserved>
            <filename> APPFILE </filename>
            <unique_guid> APPUUID </unique_guid>
            <description> Contains the root filesystem with kernel and initrd in /boot. </description>
        </partition>
    </device>
</partition_layout>
EOF

echo "Created XML partition configuration files:"
echo "  - $PARTITION_FILE_3_PART"
echo "  - $PARTITION_FILE_1_PART"

# Step 5: Flash USB device in the background
echo "Step 5: Select a partition layout file for flashing"
PARTITION_FILES=("tools/kernel_flash/flash_l4t_external.xml" "$PARTITION_FILE_3_PART" "$PARTITION_FILE_1_PART")

for i in "${!PARTITION_FILES[@]}"; do
  echo "$((i + 1)): ${PARTITION_FILES[i]}"
done

read -p "Enter the number corresponding to the partition layout file: " LAYOUT_INDEX
LAYOUT_INDEX=$((LAYOUT_INDEX - 1))

if [ -z "${PARTITION_FILES[$LAYOUT_INDEX]}" ]; then
  echo "Invalid selection."
  exit 1
fi

LAYOUT_FILE="${PARTITION_FILES[$LAYOUT_INDEX]}"
if [[ "$LAYOUT_FILE" == *3_part* ]]; then
  EXTERNAL_DEVICE="sda3"
else
  EXTERNAL_DEVICE="sda1"
fi

echo "Flashing USB with layout: $LAYOUT_FILE and external device: $EXTERNAL_DEVICE"
sudo ./tools/kernel_flash/l4t_initrd_flash.sh -c "$LAYOUT_FILE" --flash-only --external-device "$EXTERNAL_DEVICE" --direct "$USB_PATH" jetson-agx-orin-devkit external &
FLASH_PID=$!

# Step 6: Flash the Jetson bootloader
echo "Step 6: Flashing Jetson bootloader"
echo "To put the Jetson into recovery mode, hold the reset button for 5 seconds after pressing it once."
read -p "Press Enter to continue after the Jetson is in recovery mode."

echo "Using external device: $EXTERNAL_DEVICE"
sudo ./flash.sh -r -c bootloader/t186ref/cfg/flash_t234_qspi.xml --no-systemimg jetson-agx-orin-devkit "$EXTERNAL_DEVICE" || {
  echo "Bootloader flash failed. Exiting."
  exit 1
}

# Wait for USB flashing to complete
wait $FLASH_PID
echo "USB flashing completed."

# Step 7: Finish
echo "Step 7: Operation completed successfully!"
exit 0

