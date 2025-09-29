#!/usr/bin/env bash
set -euo pipefail

# defaults
default_l4t_dir="cartken_flash/Linux_for_Tegra"
default_images_dir="robot_images"
default_user="cartken"
INTERFACES=(wlan0 modem1 modem2 modem3)
REMOTE_PATH=""  # not used here

# init
dist_l4t_dir="$default_l4t_dir"
images_base="$default_images_dir"
robot_id=""
password=""

usage() {
  cat <<EOF
Usage: $0 \
  --robot N \
  --password PASS \
  [--l4t-dir DIR] \
  [--images-dir DIR]

  --robot       Robot number to flash (required)
  --password    Password for sudo on robot via ssh (required)
  --l4t-dir     Path to L4T rootfs (default: $default_l4t_dir)
  --images-dir  Base dir of saved images (default: $default_images_dir)
EOF
  exit 1
}

# parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --robot)
      robot_id="$2"; shift 2;;
    --password)
      password="$2"; shift 2;;
    --l4t-dir)
      dist_l4t_dir="$2"; shift 2;;
    --images-dir)
      images_base="$2"; shift 2;;
    -h|--help)
      usage;;
    *)
      echo "Unknown arg: $1" >&2; usage;;
  esac
done

: "${robot_id:?--robot required}"
: "${password:?--password required}"

target_images_dir="$images_base/$robot_id"

# must run as root locally
test "$EUID" -eq 0 || { echo "❌ must be run as root" >&2; exit 1; }

# prompt for physical robot
read -rp "Is this Jetson inside a physical robot whilst it is being flashed? [y/N] " yn
case "$yn" in
  [Yy]*)
    # obtain IP of robot
    echo "Resolving IP for robot $robot_id..."
    ip_out=$(timeout 5s cartken r ip "$robot_id" 2>&1) || true
    echo "$ip_out"
    robot_ip=""
    while read -r iface ip _; do
      for want in "${INTERFACES[@]}"; do
        [[ "$iface" != "$want" ]] && continue
        echo "Testing $iface ($ip)..."
        if ping -c1 -W2 "$ip" &>/dev/null; then
          robot_ip="$ip"
          echo "Selected $iface ($ip)"
          break 2
        fi
      done
    done <<< "$ip_out"
    if [[ -z "$robot_ip" ]]; then
      echo "❌ Could not reach robot $robot_id" >&2
      exit 1
    fi
    # disable watchdog via ssh + sudo
    echo "Disabling watchdog on robot $robot_ip..."
    sshpass -p "$password" ssh -o StrictHostKeyChecking=no "$default_user@$robot_ip" \
      "echo '$password' | sudo -S cartken-toggle-watchdog off"
    sshpass -p "$password" ssh -o StrictHostKeyChecking=no "$default_user@$robot_ip" \
      "echo '$password' | sudo -S cansend can1 610#2f2b210950"
    ;;
  *)
    echo "Skipping watchdog disable.";;
esac

# prompt for recovery mode
read -rp "Place the robot into recovery mode and press ENTER to continue..."

# restore images
echo "Restoring system images into $dist_l4t_dir from $target_images_dir..."
./restore_system_images.sh \
  --l4t-dir "$dist_l4t_dir" \
  --images-dir "$images_base" \
  --robot "$robot_id"

# flash
echo "Flashing Jetson..."
./flash_jetson.sh \
  --l4t-dir "$dist_l4t_dir"

echo "✓ Robot $robot_id flash complete."

