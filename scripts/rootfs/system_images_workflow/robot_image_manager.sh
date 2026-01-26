#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Robot Image Manager
#
# A single script to handle the creation and flashing of system images for
# Jetson-based robots.
#
# MODES:
#   prepare   - Prepares system images for one or more robots.
#   flash     - Flashes a robot with a previously prepared image.
# ==============================================================================


# --- Defaults & Constants ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_L4T_DIR="$SCRIPT_DIR/cartken_flash/Linux_for_Tegra"
DEFAULT_IMAGES_DIR="robot_images"
DEFAULT_VPN_DIR="robot_credentials"
DEFAULT_SSH_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINWZqz53cFupV4m8yzdveB6R8VgM17OKDuznTRaKxHIx info@cartken.com'
REMOTE_CRT_PATH="/etc/openvpn/cartken/2.0/crt"
DEFAULT_ROOTFS_GID="1-MEJNanz2eWXEhm5JC2tyiCAf8BLX_9h"
DEFAULT_FLASH_USER="cartken"
FLASH_INTERFACES=(wlan0 modem1 modem2 modem3)


# --- HELPERS: General Purpose ---

# Print usage information and exit.
usage() {
  cat <<EOF
Usage: $0 <mode> [options...]

MODES:
  prepare   Prepare system images for one or more robots.
  flash     Flash a robot using a previously prepared image.

GENERAL OPTIONS:
  --debug           Enable debug mode (prints every command).
  -h, --help        Show this help message.

--- PREPARE MODE ---
Usage: $0 prepare --robots R1,R2,... [OPTIONS]

Required:
  --robots R1,R2,...    Comma-separated list of robot IDs.

Credential Options (choose one):
  --credentials-zip ZIP   Path to a zip file with robot credentials.
  --credentials-dir DIR   Path to a directory with robot credentials.
  --fetch-credentials     Fetch credentials from live robots (requires --password).

Other Options:
  --password PASS         Password for sshpass (only with --fetch-credentials).
  --l4t-dir DIR           Path to Linux_for_Tegra dir (default: $DEFAULT_L4T_DIR).
  --images-dir DIR        Root directory for saving images (default: $DEFAULT_IMAGES_DIR).
  --rootfs-gid GID        Google Drive file ID for the rootfs tarball.
  --ssh-key "KEY"         SSH public key to inject.
  --tar PATH              Use a local L4T tarball instead of downloading.

--- FLASH MODE ---
Usage: $0 flash --robot N [OPTIONS]

Required:
  --robot N               Robot number to flash.
  --password PASS         Sudo password for the robot (for watchdog disable).

Options:
  --l4t-dir DIR           Path to Linux_for_Tegra dir (default: $DEFAULT_L4T_DIR).
  --images-dir DIR        Base dir of saved images (default: $DEFAULT_IMAGES_DIR).
  --user                  User for SSH connection (default: $DEFAULT_FLASH_USER).

Use "$0 <mode> --help" for more details on a specific mode.

EXAMPLES:

  # Prepare images for robots 302 and 305, using credentials from a zip file
  $0 prepare --robots 302,305 --credentials-zip /path/to/creds.zip

  # Prepare images for robot 309, fetching credentials from the live robot
  $0 prepare --robots 309 --fetch-credentials --password "robot_ssh_password"

  # Flash robot 302 using previously prepared images
  $0 flash --robot 302 --password "robot_sudo_password"
EOF
  exit 1
}

# Convert a path to an absolute path.
to_absolute_path() {
  local path="$1"
  if [[ "$path" != /* ]]; then
    echo "$(realpath -s "$path")"
  else
    echo "$path"
  fi
}

# Request sudo credentials if not already root.
ensure_sudo() {
  if [[ $EUID -ne 0 ]]; then
    echo "Requesting sudo for required operations..."
    if ! sudo -v; then
      echo "❌ Sudo credentials required." >&2
      exit 1
    fi
  fi
}


# --- HELPERS: PREPARE MODE ---

# Ensure L4T rootfs is downloaded and extracted.
ensure_l4t_rootfs() {
    local l4t_dir="$1"
    local rootfs_gid="$2"
    local tar_file_path="$3"

    if [[ -d "$l4t_dir" ]]; then
        echo "✓ L4T directory already exists at: $l4t_dir"
        return
    fi
    echo "L4T directory '$l4t_dir' not found. Preparing to download and extract."

    local extract_dir
    extract_dir=$(dirname "$l4t_dir")
    mkdir -p "$extract_dir"

    if [[ -z "$tar_file_path" ]]; then
        echo "No local tarball provided; downloading from Google Drive..."
        local tar_name="cartken_flash.tar.gz"
        tar_file_path="$SCRIPT_DIR/$tar_name"

        if [[ -f "$tar_file_path" ]]; then
            echo "Tarball '$tar_file_path' already exists; skipping download."
        else
            echo "Installing gdown..."
            local python_exe="python3"
            command -v python3.8 &>/dev/null && python_exe="python3.8"
            
            if grep -qi ubuntu /etc/os-release; then
                sudo apt-get update -y
                sudo apt-get install --reinstall -y python3-pip python3-setuptools python3-distutils curl
            fi
            
            local pip_opts=""
            if "$python_exe" -m pip install --help 2>&1 | grep -q -- '--break-system-packages'; then
                pip_opts="--break-system-packages"
            fi
            "$python_exe" -m pip install $pip_opts --upgrade gdown --user
            
            export PATH="$HOME/.local/bin:$PATH"
            "$python_exe" -m gdown "$rootfs_gid" -O "$tar_file_path"
        fi
    fi

    echo "Extracting '$tar_file_path' into '$extract_dir'..."
    if ! tar -xvzf "$tar_file_path" -C "$extract_dir"; then
        echo "Gzip extraction failed; trying plain tar..."
        tar -xvf "$tar_file_path" -C "$extract_dir"
    fi

    if grep -qi ubuntu /etc/os-release; then
      echo "Installing prerequisites"
      chmod +x "$l4t_dir/tools/l4t_flash_prerequisites.sh"
      sudo bash "$l4t_dir/tools/l4t_flash_prerequisites.sh"
    fi

    echo "✓ L4T directory is ready at: $l4t_dir"
}

# Fetch credentials from live robots.
fetch_credentials() {
    local robot_list="$1"
    local ssh_pass="$2"
    local output_dir="$3"
    
    echo "--- Fetching credentials from live robots ---"
    mkdir -p "$output_dir"
    
    IFS=',' read -ra robots_to_fetch <<< "$robot_list"
    for robot in "${robots_to_fetch[@]}"; do
        echo "[*] Resolving $robot …"
        local ip_out
        ip_out=$(timeout 5s cartken r ip "$robot" 2>&1) || {
            echo "⚠️  Failed to get IP for $robot"; echo "$ip_out"; continue
        }

        local robot_ip=""
        while read -r iface ip _;
 do
            for want in "${FLASH_INTERFACES[@]}"; do
                [[ "$iface" != "$want" ]] && continue
                echo "→ testing $iface ($ip)…"
                if ping -4 -c1 -W2 "$ip" &>/dev/null; then
                    robot_ip="$ip"
                    echo "✓ selected $iface ($ip)"
                    break 2
                fi
            done
        done <<< "$ip_out"

        if [[ -z "$robot_ip" ]]; then
            echo "❌ no reachable IP for $robot"
            continue
        fi

        local dest_dir="$output_dir/$robot"
        mkdir -p "$dest_dir"
        echo "[*] Pulling certs from $robot ($robot_ip)…"
        sshpass -p "$ssh_pass" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "cartken@$robot_ip:$REMOTE_CRT_PATH/robot.crt" "$dest_dir/robot.crt"
        sshpass -p "$ssh_pass" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "cartken@$robot_ip:$REMOTE_CRT_PATH/robot.key" "$dest_dir/robot.key"
    done
    echo "✓ Credential fetching complete."
}


# Configure the rootfs for a specific robot.
setup_rootfs() {
  local robot_id="$1"
  local rootfs_path="$2"
  local vpn_creds_path="$3"
  local ssh_key_to_inject="$4"

  echo "--- Configuring rootfs for robot $robot_id ---"
  ensure_sudo

  local new_hostname="cart${robot_id}jetson"
  echo "$new_hostname" | sudo tee "$rootfs_path/etc/hostname" > /dev/null
  if grep -q '^127\.0\.1\.1' "$rootfs_path/etc/hosts"; then
    sudo sed -i "s/^127\.0\.1\.1.*/127.0.1.1    $new_hostname/" "$rootfs_path/etc/hosts"
  else
    echo "127.0.1.1    $new_hostname" | sudo tee -a "$rootfs_path/etc/hosts" > /dev/null
  fi

  local env_file="$rootfs_path/etc/environment"
  if grep -q '^CARTKEN_CART_NUMBER=' "$env_file"; then
    sudo sed -i "s/^CARTKEN_CART_NUMBER=.*/CARTKEN_CART_NUMBER=$robot_id/" "$env_file"
  else
    echo "CARTKEN_CART_NUMBER=$robot_id" | sudo tee -a "$env_file" > /dev/null
  fi
  
  local hotspot_file="$rootfs_path/etc/NetworkManager/system-connections/Hotspot.nmconnection"
  if [[ -f "$hotspot_file" ]]; then
      sudo sed -i "s/^ssid=.*/ssid=$new_hostname/" "$hotspot_file"
  fi

  local auth_dir="$rootfs_path/home/cartken/.ssh"
  sudo mkdir -p "$auth_dir"
  sudo chmod 700 "$auth_dir"
  sudo touch "$auth_dir/authorized_keys"
  grep -qxF "$ssh_key_to_inject" "$auth_dir/authorized_keys" || echo "$ssh_key_to_inject" | sudo tee -a "$auth_dir/authorized_keys" > /dev/null
  sudo chmod 600 "$auth_dir/authorized_keys"
  sudo chown -R 1000:1000 "$auth_dir"

  local robot_creds_dir="$vpn_creds_path/$robot_id"
  shopt -s nullglob
  local cert_files=("$robot_creds_dir"/*.{crt,cert})
  local key_files=("$robot_creds_dir"/*.key)
  shopt -u nullglob

  if ((${#cert_files[@]} != 1)) || ((${#key_files[@]} != 1)); then
      echo "❌ Error: Expected 1 cert and 1 key file in '$robot_creds_dir', but found ${#cert_files[@]} and ${#key_files[@]}." >&2
      exit 1
  fi

  local dest_dir="$rootfs_path$REMOTE_CRT_PATH"
  sudo mkdir -p "$dest_dir"
  sudo cp -- "${cert_files[0]}" "$dest_dir/robot.crt"
  sudo cp -- "${key_files[0]}" "$dest_dir/robot.key"

  echo "✓ Rootfs configured for robot $robot_id"
}

# Generate partition images using flash.sh --no-flash.
generate_images() {
  local l4t_path="$1"
  echo "--- Generating partition images ---"
  ensure_sudo
  
  l4t_path=$(to_absolute_path "$l4t_path")
  local l4t_version; l4t_version=$(basename "$(dirname "$l4t_path")")
  
  local bootloader_partition_xml
  case "$l4t_version" in
      "6"*) bootloader_partition_xml="$l4t_path/bootloader/generic/cfg/flash_t234_qspi_sdmmc.xml";;
      *) bootloader_partition_xml="$l4t_path/bootloader/t186ref/cfg/flash_t234_qspi_sdmmc.xml";;
  esac

  # Construct absolute paths for kernel and dtb, mimicking original script
  local kernel_image; kernel_image=$(to_absolute_path "$l4t_path/kernel/Image")
  local dtb_file; dtb_file=$(to_absolute_path "$l4t_path/kernel/dtb/tegra234-p3701-0000-p3737-0000.dtb")
  bootloader_partition_xml=$(to_absolute_path "$bootloader_partition_xml")

  pushd "$l4t_path" >/dev/null
  local cmd="BOARDID=3701 BOARDSKU=0000 FAB=TS4 ./flash.sh --no-flash -c \"$bootloader_partition_xml\" -K \"$kernel_image\" -d \"$dtb_file\" jetson-agx-orin-devkit mmcblk0p1"
  echo "Running command: $cmd"

  # Temporarily disable exit-on-error to replicate original script behavior
  set +e
  sudo /bin/bash -c "$cmd"
  local flash_exit_code=$?
  set -e
  
  if [[ $flash_exit_code -ne 0 ]]; then
      echo "⚠️  WARNING: NVIDIA flash.sh script finished with a non-zero exit code ($flash_exit_code)." >&2
      echo "Proceeding based on original script behavior, but generated images may be incomplete." >&2
  fi

  popd >/dev/null
  echo "✓ Partition images generation step finished."
}

# Save generated .img files to a robot-specific directory.
save_images() {
  local robot_id="$1"
  local output_base="$2"
  local l4t_path="$3"

  echo "--- Saving images for robot $robot_id ---"
  ensure_sudo
  local target_dir="$output_base/$robot_id"
  sudo mkdir -p "$target_dir"
  
  echo "Saving .img files from '$l4t_path/bootloader' to '$target_dir'…"
  sudo find "$l4t_path/bootloader" -xdev -type f -name '*.img' -print0 | \
  while IFS= read -r -d '' IMG;
 do
    local rel_path; rel_path="${IMG#${l4t_path}/}"
    local dest_dir_inner; dest_dir_inner="$target_dir/$(dirname "$rel_path")"
    sudo mkdir -p "$dest_dir_inner"
    sudo cp -- "$IMG" "$dest_dir_inner/"
  done
  
  echo "✓ Images for robot $robot_id saved to '$target_dir'"
}



# --- HELPERS: FLASH MODE ---

# Restore saved .img files into the L4T directory for flashing.
restore_images() {
    local robot_id="$1"
    local images_base_dir="$2"
    local l4t_dir="$3"
    
    echo "--- Restoring images for robot $robot_id ---"
    ensure_sudo

    local images_dir="$images_base_dir/$robot_id"
    [[ -d "$images_dir" ]] || { echo "❌ Images dir '$images_dir' not found" >&2; exit 1; }
    
    echo "Restoring .img files from '$images_dir' into '$l4t_dir/bootloader'…"
    # Copy files from the "bootloader" subdirectory of the robot's image dir
    local source_bootloader_dir="$images_dir/bootloader"
    if [[ ! -d "$source_bootloader_dir" ]]; then
        echo "❌ No 'bootloader' subdirectory found in '$images_dir'" >&2; exit 1;
    fi

    sudo find "$source_bootloader_dir" -type f -name '*.img' -print0 | while IFS= read -r -d '' img;
 do
      local rel_path; rel_path="${img#${source_bootloader_dir}/}"
      local dest_path; dest_path="$l4t_dir/bootloader/$rel_path"
      sudo mkdir -p "$(dirname "$dest_path")"
      sudo cp -- "$img" "$dest_path"
    done

    echo "✓ All .img files for robot $robot_id restored."
}

# Flash the device using the restored images.
flash_device() {
    local l4t_dir="$1"

    echo "--- Flashing device ---"
    ensure_sudo
    
    local l4t_path; l4t_path=$(to_absolute_path "$l4t_dir")
    local l4t_version; l4t_version=$(basename "$(dirname "$l4t_path")")

    local bootloader_partition_xml
    case "$l4t_version" in
        "6"*) bootloader_partition_xml="$l4t_path/bootloader/generic/cfg/flash_t234_qspi_sdmmc.xml";;
        *) bootloader_partition_xml="$l4t_path/bootloader/t186ref/cfg/flash_t234_qspi_sdmmc.xml";;
    esac

    pushd "$l4t_path" >/dev/null
    local cmd="./flash.sh -r -c $bootloader_partition_xml -K kernel/Image -d kernel/dtb/tegra234-p3737-0000+p3701-0000.dtb jetson-agx-orin-devkit mmcblk0p1"
    echo "Running command: $cmd"
    sudo /bin/bash -c "$cmd"
    popd >/dev/null
    echo "✓ Flashing complete."
}

# Disable watchdog on a physical robot via SSH.
disable_watchdog() {
    local robot_id="$1"
    local user="$2"
    local pass="$3"
    
    echo "--- Disabling watchdog on physical robot ---"
    local ip_out
    ip_out=$(timeout 5s cartken r ip "$robot_id" 2>&1) || true
    
    local robot_ip=""
    while read -r iface ip _;
 do
          for want in "${FLASH_INTERFACES[@]}"; do
            [[ "$iface" != "$want" ]] && continue
            if ping -c1 -W2 "$ip" &>/dev/null; then
              robot_ip="$ip"
              break 2
            fi
        done
    done <<< "$ip_out"
    
    if [[ -z "$robot_ip" ]]; then
      echo "❌ Could not reach robot $robot_id. Cannot disable watchdog." >&2
      exit 1
    fi
    
    echo "Disabling watchdog on robot $robot_id at $robot_ip..."
    sshpass -p "$pass" ssh -o StrictHostKeyChecking=no "$user@$robot_ip" \
      "echo '$pass' | sudo -S cartken-toggle-watchdog off"
    sshpass -p "$pass" ssh -o StrictHostKeyChecking=no "$user@$robot_ip" \
      "echo '$pass' | sudo -S cansend can1 610#2f2b210950"
    echo "✓ Watchdog disabled."
}


# ==============================================================================
#                                  MAIN LOGIC
# ==============================================================================

# --- MAIN: PREPARE ---
main_prepare() {
    # Local variables for this mode
    local robots=""
    local l4t_dir="$DEFAULT_L4T_DIR"
    local images_dir="$DEFAULT_IMAGES_DIR"
    local rootfs_gid="$DEFAULT_ROOTFS_GID"
    local ssh_key="$DEFAULT_SSH_KEY"
    local cred_zip=""
    local vpn_dir=""
    local fetch_creds=false
    local password=""
    local tar_file=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --robots) robots="$2"; shift 2;; 
            --credentials-zip) cred_zip="$2"; shift 2;; 
            --credentials-dir) vpn_dir="$2"; shift 2;; 
            --fetch-credentials) fetch_creds=true; shift 1;; 
            --password) password="$2"; shift 2;; 
            --l4t-dir) l4t_dir="$2"; shift 2;; 
            --images-dir) images_dir="$2"; shift 2;; 
            --rootfs-gid) rootfs_gid="$2"; shift 2;; 
            --ssh-key) ssh_key="$2"; shift 2;; 
            --tar) tar_file="$2"; shift 2;; 
            -h|--help) usage; exit 0;; 
            *) echo "Unknown prepare option: $1" >&2; usage;; 
        esac
    done
    
    # Validation
    : "${robots:?--robots is required for prepare mode.}"
    
    # New validation logic to avoid set -e trap
    local cred_source_count=0
    if [[ -n "$cred_zip" ]]; then
        cred_source_count=$((cred_source_count + 1))
    fi
    if [[ -n "$vpn_dir" ]]; then
        cred_source_count=$((cred_source_count + 1))
    fi
    if [[ "$fetch_creds" == true ]]; then
        cred_source_count=$((cred_source_count + 1))
    fi

    if ((cred_source_count > 1)); then
        echo "❌ Please specify only one credential source: --credentials-zip, --credentials-dir, or --fetch-credentials." >&2
        exit 1
    fi

    if [[ "$fetch_creds" == true && -z "$password" ]]; then
        echo "❌ --password is required with --fetch-credentials." >&2; exit 1;
    fi

    # If no source was specified, use the default directory
    if ((cred_source_count == 0)); then
        vpn_dir="$DEFAULT_VPN_DIR"
    fi
    
    # Main logic
    echo "Starting PREPARE mode (v2) for robots: $robots"
    ensure_l4t_rootfs "$l4t_dir" "$rootfs_gid" "$tar_file"
    
    if [[ -n "$cred_zip" ]]; then
        echo "Unpacking credentials from zip: $cred_zip"
        vpn_dir="$SCRIPT_DIR/unzipped_credentials"
        rm -rf "$vpn_dir" && mkdir -p "$vpn_dir" && unzip -o "$cred_zip" -d "$vpn_dir"
        mapfile -t entries < <(find "$vpn_dir" -mindepth 1 -maxdepth 1)
        if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then
            mv "${entries[0]}"/* "$vpn_dir/" && rmdir "${entries[0]}"
        fi
    elif [[ "$fetch_creds" == true ]]; then
        fetch_credentials "$robots" "$password" "$vpn_dir"
    else
        [[ -d "$vpn_dir" ]] || { echo "❌ Credentials dir '$vpn_dir' not found." >&2; exit 1; }
    fi

    IFS=',' read -ra robot_array <<< "$robots"
    for r in "${robot_array[@]}"; do
        echo "=== Processing robot $r ==="
        setup_rootfs "$r" "$l4t_dir/rootfs" "$vpn_dir" "$ssh_key"
        generate_images "$l4t_dir"
        save_images "$r" "$images_dir" "$l4t_dir"
    done
    
    echo "✓ All images created successfully under $images_dir"
}

# --- MAIN: FLASH ---
main_flash() {
    # Local variables for this mode
    local robot_id=""
    local password=""
    local l4t_dir="$DEFAULT_L4T_DIR"
    local images_dir="$DEFAULT_IMAGES_DIR"
    local user="$DEFAULT_FLASH_USER"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --robot) robot_id="$2"; shift 2;; 
            --password) password="$2"; shift 2;; 
            --l4t-dir) l4t_dir="$2"; shift 2;; 
            --images-dir) images_dir="$2"; shift 2;; 
            --user) user="$2"; shift 2;; 
            -h|--help) usage; exit 0;; 
            *) echo "Unknown flash option: $1" >&2; usage;; 
        esac
    done

    # Validation
    : "${robot_id:?--robot is required for flash mode.}"
    : "${password:?--password is required for flash mode.}"
    
    # Main logic
    echo "Starting FLASH mode for robot: $robot_id"
    read -rp "Is the Jetson inside a physical robot? [y/N] " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        disable_watchdog "$robot_id" "$user" "$password"
    fi

    read -rp "Please place the robot into RECOVERY MODE, then press ENTER to continue..."
    
    restore_images "$robot_id" "$images_dir" "$l4t_dir"
    flash_device "$l4t_dir"
    
    echo "✓ Robot $robot_id flash complete."
}


# --- Command Dispatcher ---
main() {
    if [[ $# -eq 0 ]]; then
        usage
    fi

    # New array to hold args without --debug
    local processed_args=()
    for arg in "$@"; do
        if [[ "$arg" == "--debug" ]]; then
            echo "--- DEBUG MODE ENABLED ---"
            set -x
        else
            processed_args+=("$arg")
        fi
    done

    # Overwrite the original positional parameters with the new, cleaned array
    set -- "${processed_args[@]}"

    if [[ $# -eq 0 ]]; then
        usage
    fi

    local mode="$1"
    shift

    case "$mode" in
        prepare)
            main_prepare "$@"
            ;; 
        flash)
            main_flash "$@"
            ;; 
        -h|--help)
            usage
            ;; 
        *)
            echo "Unknown mode: $mode" >&2
            usage
            ;; 
    esac
}

main "$@"
