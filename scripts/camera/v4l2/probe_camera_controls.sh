#!/bin/bash

# Probe and optionally format adjustable v4l2 camera controls over SSH.
#
# Supersedes the older probe_camera_controls.sh / probe_camera_controls_formatted.sh
# / probe_camera_automatic_controls_formatted.sh trio.
#
# Usage:
#   probe_camera_controls.sh [--device-ip <ip>] [--format raw|table|auto-table]
#                            [--all | <device>]
#
# Defaults:
#   --format raw  (plain v4l2-ctl --list-ctrls-menus output)
#   device IP is read from scripts/config/device_ip if present.

FORMAT="raw"
DEVICE_IP=""
ALL=false
DEVICE=""
USERNAME="root"

show_help() {
  cat <<EOF
probe_camera_controls.sh - List adjustable v4l2 controls for one or more cameras on a remote device.

Usage:
  $0 [--device-ip <ip>] [--format raw|table|auto-table] [--all | <device>]

Options:
  --device-ip <ip>         Override the IP in scripts/config/device_ip.
  --format raw             Print raw v4l2-ctl output (default).
  --format table           Pretty-print a fixed-width table of controls.
  --format auto-table      Like table, plus a column flagging each Auto
                           control's corresponding Manual control.
  --all                    Enumerate every /dev/video* device on the target.
  <device>                 A single device path (e.g. /dev/video0).
  --help                   Show this help.

Examples:
  $0 /dev/video0
  $0 --device-ip 192.168.1.100 --format table /dev/video0
  $0 --format auto-table --all
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) show_help; exit 0 ;;
    --device-ip) DEVICE_IP="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    --all) ALL=true; shift ;;
    *)
      if [[ -z "$DEVICE" ]]; then
        DEVICE="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        show_help
        exit 1
      fi
      ;;
  esac
done

SCRIPT_DIR="$(realpath "$(dirname "$0")/../..")"
if [[ -z "$DEVICE_IP" && -f "$SCRIPT_DIR/config/device_ip" ]]; then
  DEVICE_IP=$(cat "$SCRIPT_DIR/config/device_ip")
fi
if [[ -z "$DEVICE_IP" ]]; then
  echo "Error: no device IP. Provide --device-ip or populate $SCRIPT_DIR/config/device_ip." >&2
  exit 1
fi

if [[ "$ALL" == true ]]; then
  DEVICES=$(ssh "$USERNAME@$DEVICE_IP" "ls /dev/video*" 2>/dev/null)
  if [[ -z "$DEVICES" ]]; then
    echo "No video devices found on $DEVICE_IP." >&2
    exit 1
  fi
else
  if [[ -z "$DEVICE" ]]; then
    echo "Error: specify a device path or --all." >&2
    show_help
    exit 1
  fi
  DEVICES="$DEVICE"
fi

format_table() {
  awk '
    BEGIN {
      print "---------------------------------------------------------------------------------------"
      print "| Control Name               | Current     | Range/Values                | Writable    |"
      print "---------------------------------------------------------------------------------------"
    }
    {
      name = gensub(/\(.*$/, "", "g", $1)
      name = substr(name, 1, 25)

      if (match($0, /value=([0-9]+)/, arr)) { value = arr[1] } else { value = "N/A" }

      if (match($0, /min=([0-9]+) max=([0-9]+)/, arr)) {
        range = "min=" arr[1] ", max=" arr[2]
      } else if (match($0, /\[(.+)\]/, arr)) {
        range = arr[1]
      } else {
        range = "N/A"
      }
      if (length(range) > 25) { range = substr(range, 1, 22) "..." }

      writable = /writable/ ? "Yes" : "No"
      printf "| %-25s | %-11s | %-25s | %-11s |\n", name, value, range, writable
    }
    END {
      print "---------------------------------------------------------------------------------------"
    }'
}

format_auto_table() {
  awk '
    BEGIN {
      print "-------------------------------------------------------------------------------------------------------------"
      print "| Control Name               | Current     | Range/Values                | Writable    | Related Manual Control |"
      print "-------------------------------------------------------------------------------------------------------------"
    }
    {
      name = gensub(/\(.*$/, "", "g", $1)
      name = substr(name, 1, 25)

      if (match($0, /value=([0-9]+)/, arr)) { value = arr[1] } else { value = "N/A" }

      if (match($0, /min=([0-9]+) max=([0-9]+)/, arr)) {
        range = "min=" arr[1] ", max=" arr[2]
      } else if (match($0, /\[(.+)\]/, arr)) {
        range = arr[1]
      } else {
        range = "N/A"
      }
      if (length(range) > 25) { range = substr(range, 1, 22) "..." }

      writable = /writable/ ? "Yes" : "No"

      manual_control = "N/A"
      if (match(tolower(name), /auto/)) {
        sub("Auto", "Manual", name)
        manual_control = name
      }

      printf "| %-25s | %-11s | %-25s | %-11s | %-23s |\n", $1, value, range, writable, manual_control
    }
    END {
      print "-------------------------------------------------------------------------------------------------------------"
    }'
}

for D in $DEVICES; do
  echo "Processing device: $D"
  RAW=$(ssh "$USERNAME@$DEVICE_IP" "v4l2-ctl -d '$D' --list-ctrls-menus")
  case "$FORMAT" in
    raw) echo "$RAW" ;;
    table) echo "$RAW" | format_table ;;
    auto-table) echo "$RAW" | format_auto_table ;;
    *)
      echo "Unknown --format: $FORMAT (expected raw|table|auto-table)" >&2
      exit 1
      ;;
  esac
done
