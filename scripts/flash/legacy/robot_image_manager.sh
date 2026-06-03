#!/usr/bin/env bash
set -euo pipefail

# Legacy image workflow kept separate from the current SSH-CA flashing stack.
# This script intentionally preserves the older model:
# - Prepare: download/extract prebuilt L4T tarball, configure rootfs per robot,
#   generate/save .img artifacts.
# - Flash: restore saved .img artifacts and flash a single robot.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_L4T_DIR="$SCRIPT_DIR/cartken_flash/Linux_for_Tegra"
DEFAULT_IMAGES_DIR="$SCRIPT_DIR/robot_images"
DEFAULT_CREDS_DIR="$SCRIPT_DIR/robot_credentials"
DEFAULT_ROOTFS_GID="1pcYcyXDWOgkJ4Z_OD3gDYiL0KEDrTBEL"
DEFAULT_FLASH_USER="cartken"
DEFAULT_SSH_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINWZqz53cFupV4m8yzdveB6R8VgM17OKDuznTRaKxHIx info@cartken.com'
REMOTE_CRT_PATH="/etc/openvpn/cartken/2.0/crt"
FLASH_INTERFACES=(wlan0 modem1 modem2 modem3)

usage() {
  cat <<'EOF'
Usage: ./robot_image_manager.sh <mode> [options...]

MODES:
  prepare   Build/cache per-robot image bundles.
  flash     Flash one robot from a previously prepared bundle.

GENERAL:
  --debug                     Enable shell trace output.
  -h, --help                  Show this help message.

PREPARE:
  --robots R1,R2,...          Comma-separated robots.
  --robot-range START END     Inclusive robot range.
  --flash                     After prepare, run flash flow in same invocation.
  --flash-user USER           SSH user for watchdog step during --flash (default: cartken).
  --credentials-zip ZIP       Zip containing per-robot cert/key directories.
  --credentials-dir DIR       Directory with per-robot cert/key directories.
  --crt FILE --key FILE       Reuse one cert/key pair for all selected robots.
  --fetch-credentials         Pull certs from live robots (requires --password).
  --password PASS             SSH password for --fetch-credentials.
  --l4t-dir DIR               Linux_for_Tegra path (default: legacy cartken_flash).
  --images-dir DIR            Output image cache directory.
  --rootfs-gid GID            Google Drive file id for cartken_flash tarball.
  --ssh-key "PUBKEY"          Authorized key injected into rootfs.
  --tar PATH                  Local tarball instead of Google Drive download.

FLASH:
  --robot N                   Robot number to flash.
  --password PASS             Robot sudo password (watchdog disable step).
  --l4t-dir DIR               Linux_for_Tegra path.
  --images-dir DIR            Prepared image cache directory.
  --user USER                 SSH username for watchdog step (default: cartken).
EOF
}

to_abs() {
  local p="$1"
  if [[ "$p" != /* ]]; then
    realpath -s "$p"
  else
    echo "$p"
  fi
}

ensure_gdown() {
  local py="python3"
  command -v python3.8 >/dev/null 2>&1 && py="python3.8"

  if ! "$py" -m gdown --help >/dev/null 2>&1; then
    if grep -qi ubuntu /etc/os-release; then
      sudo apt-get update -y
      sudo apt-get install --reinstall -y python3-pip python3-setuptools python3-distutils curl
    fi
    local pip_opts=""
    if "$py" -m pip install --help 2>&1 | grep -q -- '--break-system-packages'; then
      pip_opts="--break-system-packages"
    fi
    "$py" -m pip install $pip_opts --upgrade gdown --user
  fi
}

ensure_l4t_rootfs() {
  local l4t_dir="$1"
  local rootfs_gid="$2"
  local tar_file="$3"

  if [[ -d "$l4t_dir" ]]; then
    echo "Using existing L4T directory: $l4t_dir"
    return
  fi

  local extract_dir
  extract_dir="$(dirname "$l4t_dir")"
  mkdir -p "$extract_dir"

  if [[ -z "$tar_file" ]]; then
    tar_file="$SCRIPT_DIR/cartken_flash.tar.gz"
    if [[ ! -f "$tar_file" ]]; then
      ensure_gdown
      local py="python3"
      command -v python3.8 >/dev/null 2>&1 && py="python3.8"
      "$py" -m gdown "$rootfs_gid" -O "$tar_file"
    fi
  fi

  tar -xvzf "$tar_file" -C "$extract_dir" || tar -xvf "$tar_file" -C "$extract_dir"
  if [[ -f "$l4t_dir/tools/l4t_flash_prerequisites.sh" ]]; then
    sudo bash "$l4t_dir/tools/l4t_flash_prerequisites.sh"
  fi
}

resolve_robot_ip() {
  local robot="$1"
  local out ip iface line
  out="$(timeout 5s cartken r ip "$robot" 2>&1 || true)"
  while IFS= read -r line; do
    iface="$(awk '{print $1}' <<<"$line")"
    ip="$(awk '{print $2}' <<<"$line")"
    for want in "${FLASH_INTERFACES[@]}"; do
      [[ "$iface" != "$want" ]] && continue
      if ping -4 -c1 -W2 "$ip" >/dev/null 2>&1; then
        echo "$ip"
        return 0
      fi
    done
  done <<<"$out"
  return 1
}

setup_rootfs_for_robot() {
  local robot="$1" rootfs="$2" creds_dir="$3" ssh_key="$4"
  local host="cart${robot}jetson"

  echo "[robot $robot] Applying rootfs customization..."
  echo "[robot $robot] - hostname: $host"
  echo "$host" | sudo tee "$rootfs/etc/hostname" >/dev/null
  if grep -q '^127\.0\.1\.1' "$rootfs/etc/hosts"; then
    sudo sed -i "s/^127\.0\.1\.1.*/127.0.1.1    $host/" "$rootfs/etc/hosts"
  else
    echo "127.0.1.1    $host" | sudo tee -a "$rootfs/etc/hosts" >/dev/null
  fi

  echo "[robot $robot] - environment: CARTKEN_CART_NUMBER=$robot"
  if grep -q '^CARTKEN_CART_NUMBER=' "$rootfs/etc/environment"; then
    sudo sed -i "s/^CARTKEN_CART_NUMBER=.*/CARTKEN_CART_NUMBER=$robot/" "$rootfs/etc/environment"
  else
    echo "CARTKEN_CART_NUMBER=$robot" | sudo tee -a "$rootfs/etc/environment" >/dev/null
  fi

  echo "[robot $robot] - injecting legacy SSH key into cartken authorized_keys"
  local auth_dir="$rootfs/home/cartken/.ssh"
  sudo mkdir -p "$auth_dir"
  sudo chmod 700 "$auth_dir"
  sudo touch "$auth_dir/authorized_keys"
  if ! sudo grep -qxF "$ssh_key" "$auth_dir/authorized_keys" >/dev/null 2>&1; then
    echo "$ssh_key" | sudo tee -a "$auth_dir/authorized_keys" >/dev/null
  fi
  sudo chmod 600 "$auth_dir/authorized_keys"
  sudo chown -R 1000:1000 "$auth_dir"

  local robot_creds="$creds_dir/$robot"
  local cert key
  cert="$(ls "$robot_creds"/*.crt "$robot_creds"/*.cert 2>/dev/null | head -n1 || true)"
  key="$(ls "$robot_creds"/*.key 2>/dev/null | head -n1 || true)"
  [[ -n "$cert" && -n "$key" ]] || { echo "Missing cert/key under $robot_creds" >&2; exit 1; }

  local vpn_dest="$rootfs$REMOTE_CRT_PATH"
  echo "[robot $robot] - VPN cert/key source: $robot_creds"
  sudo mkdir -p "$vpn_dest"
  sudo cp "$cert" "$vpn_dest/robot.crt"
  sudo cp "$key" "$vpn_dest/robot.key"
  echo "[robot $robot] Rootfs customization complete."
}

generate_and_save_images() {
  local robot="$1" l4t_dir="$2" images_dir="$3"
  local version boot_xml
  version="$(basename "$(dirname "$l4t_dir")")"
  case "$version" in
    6*) boot_xml="$l4t_dir/bootloader/generic/cfg/flash_t234_qspi_sdmmc.xml" ;;
    *) boot_xml="$l4t_dir/bootloader/t186ref/cfg/flash_t234_qspi_sdmmc.xml" ;;
  esac

  # Allow image generation without a Jetson connected by providing the module
  # identifiers explicitly (legacy behavior from the pre-v2 workflow).
  echo "[robot $robot] Generating partition images (--no-flash)..."
  (
    cd "$l4t_dir" && \
    sudo BOARDID=3701 BOARDSKU=0000 FAB=TS4 \
      ./flash.sh --no-flash -c "$boot_xml" \
      -K "$l4t_dir/kernel/Image" \
      -d "$l4t_dir/kernel/dtb/tegra234-p3701-0000-p3737-0000.dtb" \
      jetson-agx-orin-devkit mmcblk0p1
  ) || true

  local out="$images_dir/$robot"
  echo "[robot $robot] Saving generated .img files to: $out"
  sudo mkdir -p "$out"
  sudo find "$l4t_dir/bootloader" -xdev -type f -name '*.img' -print0 | while IFS= read -r -d '' img; do
    local rel="${img#${l4t_dir}/}"
    sudo mkdir -p "$out/$(dirname "$rel")"
    sudo cp "$img" "$out/$rel"
  done
  echo "[robot $robot] Image bundle ready."
}

prepare_mode() {
  local robots="" range_start="" range_end=""
  local l4t_dir="$DEFAULT_L4T_DIR" images_dir="$DEFAULT_IMAGES_DIR"
  local rootfs_gid="$DEFAULT_ROOTFS_GID" ssh_key="$DEFAULT_SSH_KEY"
  local cred_zip="" cred_dir="" fetch_creds=false password="" tar_file="" crt_file="" key_file=""
  local auto_flash=false flash_user="$DEFAULT_FLASH_USER"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --robots) robots="$2"; shift 2 ;;
      --robot-range) range_start="$2"; range_end="$3"; shift 3 ;;
      --flash) auto_flash=true; shift ;;
      --flash-user) flash_user="$2"; shift 2 ;;
      --credentials-zip) cred_zip="$2"; shift 2 ;;
      --credentials-dir) cred_dir="$2"; shift 2 ;;
      --crt) crt_file="$2"; shift 2 ;;
      --key) key_file="$2"; shift 2 ;;
      --fetch-credentials) fetch_creds=true; shift ;;
      --password) password="$2"; shift 2 ;;
      --l4t-dir) l4t_dir="$2"; shift 2 ;;
      --images-dir) images_dir="$2"; shift 2 ;;
      --rootfs-gid) rootfs_gid="$2"; shift 2 ;;
      --ssh-key) ssh_key="$2"; shift 2 ;;
      --tar) tar_file="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown prepare option: $1" >&2; usage; exit 1 ;;
    esac
  done

  [[ -n "$robots" || -n "$range_start" ]] || { echo "Missing robot selection." >&2; exit 1; }
  if [[ -n "$range_start" ]]; then
    robots="$(seq "$range_start" "$range_end" | paste -sd, -)"
  fi
  if [[ "$auto_flash" == true && -z "$password" ]]; then
    echo "--flash requires --password (used by the watchdog/SSH step)." >&2
    exit 1
  fi

  l4t_dir="$(to_abs "$l4t_dir")"
  images_dir="$(to_abs "$images_dir")"
  [[ -n "$tar_file" ]] && tar_file="$(to_abs "$tar_file")"

  ensure_l4t_rootfs "$l4t_dir" "$rootfs_gid" "$tar_file"
  mkdir -p "$images_dir"

  local working_creds="$cred_dir"
  if [[ -n "$cred_zip" ]]; then
    working_creds="$SCRIPT_DIR/robot_credentials"
    rm -rf "$working_creds"
    mkdir -p "$working_creds"
    unzip -o "$cred_zip" -d "$working_creds" >/dev/null
  elif [[ "$fetch_creds" == true ]]; then
    [[ -n "$password" ]] || { echo "--password is required with --fetch-credentials" >&2; exit 1; }
    working_creds="$SCRIPT_DIR/robot_credentials"
    rm -rf "$working_creds"
    mkdir -p "$working_creds"
    IFS=',' read -ra robot_arr <<<"$robots"
    for r in "${robot_arr[@]}"; do
      ip="$(resolve_robot_ip "$r" || true)"
      [[ -n "$ip" ]] || { echo "Could not resolve reachable IP for robot $r" >&2; continue; }
      mkdir -p "$working_creds/$r"
      sshpass -p "$password" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "cartken@$ip:$REMOTE_CRT_PATH/robot.crt" "$working_creds/$r/robot.crt"
      sshpass -p "$password" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "cartken@$ip:$REMOTE_CRT_PATH/robot.key" "$working_creds/$r/robot.key"
    done
  elif [[ -n "$crt_file" || -n "$key_file" ]]; then
    [[ -n "$crt_file" && -n "$key_file" ]] || { echo "Both --crt and --key are required together." >&2; exit 1; }
    working_creds="$SCRIPT_DIR/robot_credentials"
    rm -rf "$working_creds"
    mkdir -p "$working_creds"
    IFS=',' read -ra robot_arr <<<"$robots"
    for r in "${robot_arr[@]}"; do
      mkdir -p "$working_creds/$r"
      cp "$crt_file" "$working_creds/$r/robot.crt"
      cp "$key_file" "$working_creds/$r/robot.key"
    done
  fi

  [[ -n "$working_creds" && -d "$working_creds" ]] || { echo "Credential directory not found." >&2; exit 1; }

  IFS=',' read -ra robot_arr <<<"$robots"
  for r in "${robot_arr[@]}"; do
    echo "============================================================"
    echo "Preparing legacy image bundle for robot: $r"
    setup_rootfs_for_robot "$r" "$l4t_dir/rootfs" "$working_creds" "$ssh_key"
    generate_and_save_images "$r" "$l4t_dir" "$images_dir"
    if [[ "$auto_flash" == true ]]; then
      echo "[robot $r] --flash enabled: launching flash step now..."
      flash_mode --robot "$r" --password "$password" --l4t-dir "$l4t_dir" --images-dir "$images_dir" --user "$flash_user"
    fi
  done
  if [[ "$auto_flash" == true ]]; then
    echo "Legacy prepare+flash complete for robot(s): $robots"
  else
    echo "Legacy prepare complete for robot(s): $robots"
  fi
}

flash_mode() {
  local robot="" password="" l4t_dir="$DEFAULT_L4T_DIR" images_dir="$DEFAULT_IMAGES_DIR" user="$DEFAULT_FLASH_USER"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --robot) robot="$2"; shift 2 ;;
      --password) password="$2"; shift 2 ;;
      --l4t-dir) l4t_dir="$2"; shift 2 ;;
      --images-dir) images_dir="$2"; shift 2 ;;
      --user) user="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown flash option: $1" >&2; usage; exit 1 ;;
    esac
  done
  [[ -n "$robot" && -n "$password" ]] || { echo "--robot and --password are required." >&2; exit 1; }

  l4t_dir="$(to_abs "$l4t_dir")"
  images_dir="$(to_abs "$images_dir")"
  local src="$images_dir/$robot/bootloader"
  [[ -d "$src" ]] || { echo "Prepared images not found: $src" >&2; exit 1; }

  read -rp "Is the Jetson inside a physical robot? [y/N] " yn
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    ip="$(resolve_robot_ip "$robot" || true)"
    if [[ -n "$ip" ]]; then
      sshpass -p "$password" ssh -o StrictHostKeyChecking=no "$user@$ip" \
        "echo '$password' | sudo -S cartken-toggle-watchdog off"
    fi
  fi

  sudo find "$src" -type f -name '*.img' -print0 | while IFS= read -r -d '' img; do
    local rel="${img#${src}/}"
    local dest="$l4t_dir/bootloader/$rel"
    sudo mkdir -p "$(dirname "$dest")"
    sudo cp "$img" "$dest"
  done

  local version boot_xml
  version="$(basename "$(dirname "$l4t_dir")")"
  case "$version" in
    6*) boot_xml="$l4t_dir/bootloader/generic/cfg/flash_t234_qspi_sdmmc.xml" ;;
    *) boot_xml="$l4t_dir/bootloader/t186ref/cfg/flash_t234_qspi_sdmmc.xml" ;;
  esac

  read -rp "Put the robot in recovery mode and press Enter..."
  ( cd "$l4t_dir" && sudo ./flash.sh -r -c "$boot_xml" \
      -K "$l4t_dir/kernel/Image" \
      -d "$l4t_dir/kernel/dtb/tegra234-p3701-0000-p3737-0000.dtb" \
      jetson-agx-orin-devkit mmcblk0p1 )
}

main() {
  [[ $# -gt 0 ]] || { usage; exit 1; }

  local args=()
  for a in "$@"; do
    if [[ "$a" == "--debug" ]]; then
      set -x
    else
      args+=("$a")
    fi
  done
  set -- "${args[@]}"

  local mode="$1"; shift
  case "$mode" in
    prepare) prepare_mode "$@" ;;
    flash) flash_mode "$@" ;;
    -h|--help) usage ;;
    *) echo "Unknown mode: $mode" >&2; usage; exit 1 ;;
  esac
}

main "$@"
