#!/bin/bash

set -e

if [[ "$EUID" -ne 0 ]]; then
    echo "Error: This script must be run with sudo."
    exit 1
fi

# Default values
DRY_RUN=false
DEPLOY_IP=""
BASE_BSP=""
TARGET_BSP=""
FORCE_PARTITION_CHANGE=false
PARTITION_XML=""
BUILD_BOOTLOADER=false
BUILD_ROOTFS=false
SKIP_BUILD=false

declare -A BSP_VERSION_MAP=(
    [5.1.2]="R35-4"
    [5.1.3]="R35-5"
    [5.1.4]="R35-6"
    [5.1.5]="R35-6"
    [6.0DP]="R36-2"
    [6.2]="R36-2"
)

declare -A OTA_TOOL_URLS=(
    [5.1.2]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/release/ota_tools_r35.4.1_aarch64.tbz2"
    [5.1.3]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v5.0/release/ota_tools_R35.5.0_aarch64.tbz2"
	[5.1.4]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.0/release/ota_tools_R35.6.0_aarch64.tbz2"
	[5.1.5]="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.1/release/ota_tools_R35.6.1_aarch64.tbz2"
    [6.0DP]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v3.0/release/ota_tools_R36.3.0_aarch64.tbz2"
    [6.2]="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/release/ota_tools_r36.4.3_aarch64.tbz2"
)

show_help() {
    echo "Usage: $0 --base-bsp <path> --target-bsp <path> [--deploy <device-ip>] [--dry-run] [--force-partition-change]"
    echo "Options:"
    echo "  --base-bsp PATH              Path to the BASE BSP source (e.g., 5.1.2)"
    echo "  --target-bsp PATH            Path to the TARGET BSP source (e.g., 5.1.3)"
    echo "  --deploy IP                  Deploy the generated OTA update to the given device IP (e.g., 192.168.1.91)"
    echo "  --dry-run                    Show commands that would be executed without running them"
    echo "  --force-partition-change     Modify l4t_generate_ota_package.sh to enable partition changes"
	echo "  --partition-xml FILE         Path to a partition XML file to replace the default one in the target BSP"
	echo "  --skip-build				 Skips the building of the package (assumes it already exists)"
	echo "  -b                           Build only the bootloader"
    echo "  -r                           Build only the rootfs"
    exit 0
}

run_cmd() {
    if $DRY_RUN; then
        echo "[DRY-RUN] sudo $1"
    else
        sudo bash -c "$1"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-bsp)
            BASE_BSP=$(realpath "$2")
            shift 2
            ;;
        --target-bsp)
            TARGET_BSP=$(realpath "$2")
            shift 2
            ;;
        --deploy)
            DEPLOY_IP="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force-partition-change)
            FORCE_PARTITION_CHANGE=true
            shift
            ;;
		--partition-xml)
            PARTITION_XML=$(realpath "$2")
            shift 2
            ;;
		--skip-build)
            SKIP_BUILD=true
            shift
            ;;
		-b)
            BUILD_BOOTLOADER=true
            shift
            ;;
        -r)
            BUILD_ROOTFS=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

if [[ -z "$BASE_BSP" || -z "$TARGET_BSP" ]]; then
    echo "Error: Both --base-bsp and --target-bsp must be provided."
    exit 1
fi

BASE_VERSION=$(basename "$BASE_BSP")
TARGET_VERSION=$(basename "$TARGET_BSP")
BASE_L4T="$BASE_BSP/Linux_for_Tegra"
TARGET_L4T="$TARGET_BSP/Linux_for_Tegra"
export BASE_BSP=$BASE_L4T
export TARGET_BSP=$TARGET_L4T
BASE_BSP_VERSION="${BSP_VERSION_MAP[$BASE_VERSION]}"

echo "BASE L4T: $BASE_L4T"

if [[ -z "$BASE_BSP_VERSION" ]]; then
    echo "Error: Unsupported BASE_BSP version ($BASE_VERSION)."
    exit 1
fi

# Get correct OTA tool URL for TARGET_BSP
OTA_TOOL_URL="${OTA_TOOL_URLS[$TARGET_VERSION]}"
OTA_TOOL_FILE="$(basename "$OTA_TOOL_URL")"
# Ensure absolute paths before changing directories
OTA_TOOL_FILE_PATH="$PWD/$OTA_TOOL_FILE"
PAYLOAD_PATH="$TARGET_BSP/bootloader/jetson-agx-orin-devkit/ota_payload_package.tar.gz"

# Download OTA tools if missing (wget does not need sudo)
if [[ ! -f "$OTA_TOOL_FILE" ]]; then
    echo "Downloading OTA tools for target BSP $TARGET_VERSION..."
    if $DRY_RUN; then
        echo "[DRY-RUN] wget -O \"$OTA_TOOL_FILE\" \"$OTA_TOOL_URL\""
    else
        wget -O "$OTA_TOOL_FILE" "$OTA_TOOL_URL"
    fi
else
    echo "OTA tools already downloaded."
fi

# Extract OTA tools directly into TARGET_BSP
echo "Extracting OTA tools into "$TARGET_L4T"..."
run_cmd "tar xpf \"$OTA_TOOL_FILE\" -C \"$(dirname "$TARGET_L4T")\""

# OTA_BOARD_SPECS="$TARGET_L4T/tools/ota_tools/version_upgrade/ota_board_specs.conf"
# # Remove other board configs to speed up OTA generation ~x5
# #sed -i '/^jetson_agx_orin_devkit_ota_emmc_r35_spec=/,/^)/ {/boardid=3701;fab=000;boardsku=0000;.*rootdev=mmcblk0p1;/!{/^jetson_agx_orin_devkit_ota_emmc_r35_spec=/!{/^)/!d}}}' "$OTA_BOARD_SPECS"
#
# sed -i '/^jetson_agx_orin_devkit_ota_emmc_r35_spec=/,/^)/ {
#   /boardid=3701;fab=000;boardsku=0000;.*rootdev=mmcblk0p1;/b
#   /boardid=3701;fab=300;boardsku=0000;.*rootdev=mmcblk0p1;/b
#   /boardid=3701;fab=300;boardsku=0005;.*rootdev=mmcblk0p1;/b
#   /^jetson_agx_orin_devkit_ota_emmc_r35_spec=/b
#   /^)/b
#   d
# }' "$OTA_BOARD_SPECS"

# Replace partition XML if provided
if [[ -n "$PARTITION_XML" ]]; then
	TARGET_PARTITION_XML="$TARGET_L4T/bootloader/t186ref/cfg/flash_t234_qspi_sdmmc.xml"
	echo "Replacing partition XML file..."
	echo "cp \"$PARTITION_XML\" \"$TARGET_PARTITION_XML\""
	run_cmd "cp \"$PARTITION_XML\" \"$TARGET_PARTITION_XML\""
fi

# Remove specific line from ota_make_recovery_img_dtb.sh
OTA_SCRIPT="${TARGET_L4T}/tools/ota_tools/version_upgrade/ota_make_recovery_img_dtb.sh"
if [[ -f "$OTA_SCRIPT" ]]; then
    echo "Removing problematic line from $OTA_SCRIPT..."
	run_cmd "sudo sed -i '/ssh-keygen[[:space:]]\+-t[[:space:]]\+dsa[[:space:]]\+-N/d' \"$OTA_SCRIPT\""
else
    echo "Warning: $OTA_SCRIPT not found. Skipping modification."
fi

# Apply force partition change if requested
if $FORCE_PARTITION_CHANGE; then
    echo "Enabling partition layout change..."
    run_cmd "sed -i 's/^LAYOUT_CHANGE=0/LAYOUT_CHANGE=1/' \"$TARGET_L4T/tools/ota_tools/version_upgrade/l4t_generate_ota_package.sh\""
fi

# Determine OTA build arguments
OTA_BUILD_ARGS=""
if $BUILD_BOOTLOADER; then
    OTA_BUILD_ARGS+=" -b"
fi
if $BUILD_ROOTFS; then
    OTA_BUILD_ARGS+=" -r"
fi

DTB_PATH="$TARGET_L4T/kernel/dtb/tegra234-p3701-0000-p3737-0000.dtb"

# Generate OTA payload
if ! $SKIP_BUILD; then
    echo "Generating OTA update payload..."
	if [[ -n "$DTB_PATH" && "$BASE_BSP_VERSION" != "R35-4" ]]; then
		FLASH_OPTS="-p \"-d $DTB_PATH\""
	else
		FLASH_OPTS=""
	fi

	echo "cd \"$TARGET_L4T\" && BASE_BSP="$BASE_BSP" TARGET_BSP="$TARGET_BSP" ./tools/ota_tools/version_upgrade/l4t_generate_ota_package.sh $OTA_BUILD_ARGS $FLASH_OPTS jetson-agx-orin-devkit $BASE_BSP_VERSION"
	run_cmd "cd \"$TARGET_L4T\" && BASE_BSP=$BASE_BSP TARGET_BSP=$TARGET_BSP ./tools/ota_tools/version_upgrade/l4t_generate_ota_package.sh $OTA_BUILD_ARGS $FLASH_OPTS jetson-agx-orin-devkit $BASE_BSP_VERSION"

    # echo "$TARGET_L4T/tools/ota_tools/version_upgrade/l4t_generate_ota_package.sh jetson-agx-orin-devkit $BASE_BSP_VERSION"
    # run_cmd "cd \"$TARGET_L4T\" && ./tools/ota_tools/version_upgrade/l4t_generate_ota_package.sh $OTA_BUILD_ARGS jetson-agx-orin-devkit $BASE_BSP_VERSION"
else
    echo "Skipping OTA update payload generation (--skip-build enabled)."
fi


# Find the generated payload
PAYLOAD_PATH="$TARGET_L4T/bootloader/jetson-agx-orin-devkit/ota_payload_package.tar.gz"
if [[ ! -f "$PAYLOAD_PATH" && "$DRY_RUN" == false ]]; then
    echo "Error: Failed to generate OTA payload!"
    exit 1
fi

echo "OTA payload generated successfully: $PAYLOAD_PATH"

# Deploy OTA update if --deploy is provided
if [[ -n "$DEPLOY_IP" ]]; then
    echo "Deploying OTA update to Jetson device at $DEPLOY_IP..."

	if $DRY_RUN; then
        echo "[DRY-RUN] scp \"$OTA_TOOL_FILE_PATH\" root@$DEPLOY_IP:/home/root/"
        echo "[DRY-RUN] scp \"$PAYLOAD_PATH\" root@$DEPLOY_IP:/home/root/"
    else
        echo "scp "$OTA_TOOL_FILE_PATH" root@$DEPLOY_IP:/root/"
        scp "$OTA_TOOL_FILE_PATH" root@$DEPLOY_IP:/root/
        echo "scp "$PAYLOAD_PATH" root@$DEPLOY_IP:/root/"
        scp "$PAYLOAD_PATH" root@$DEPLOY_IP:/root/
    fi


    run_cmd "ssh root@$DEPLOY_IP 'mkdir -p /root/ota_update && tar -xjf \"/root/$OTA_TOOL_FILE\" -C /root/ota_update'"
    run_cmd "ssh root@$DEPLOY_IP 'sudo mkdir -p /ota && sudo mv /root/ota_payload_package.tar.gz /ota/'"

    echo "Executing OTA update..."
    run_cmd "ssh root@$DEPLOY_IP 'cd /root/ota_update/Linux_for_Tegra/tools/ota_tools/version_upgrade && sudo ./nv_ota_start.sh /ota/ota_payload_package.tar.gz'"

    echo "Deployment completed!"
fi

echo "Script execution finished."

