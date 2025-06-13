#!/usr/bin/env bash
set -euo pipefail

# defaults
INTERFACES=(wlan0 modem1 modem2 modem3)
REMOTE_PATH="/etc/openvpn/cartken/2.0/crt"
TMP_CRT_DIR="robot_credentials"

usage() {
  cat <<EOF
Usage: $0 --robots R1,R2,... --password PASS [--output DIR]

  --robots    Comma-separated robot names/IDs
  --password  Password for sshpass
  --output    Base directory to save crts (default: $TMP_CRT_DIR)

Inside \$OUTPUT, each robot will get its own subfolder:
  \$OUTPUT/<robot>/robot.crt
  \$OUTPUT/<robot>/robot.key
EOF
  exit 1
}

# parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --robots)   ROBOT_LIST="$2"; shift 2;;
    --password) PASSWORD="$2";   shift 2;;
    --output)   TMP_CRT_DIR="$2"; shift 2;;
    -h|--help)  usage;;
    *)          echo "Unknown arg: $1" >&2; usage;;
  esac
done

[[ -z "${ROBOT_LIST:-}" ]] && echo "--robots is required" >&2 && usage
[[ -z "${PASSWORD:-}"   ]] && echo "--password is required" >&2 && usage

mkdir -p "$TMP_CRT_DIR"

IFS=',' read -ra ROBOTS <<< "$ROBOT_LIST"
for ROBOT in "${ROBOTS[@]}"; do
  echo "[*] Resolving $ROBOT…"
  IP_OUT=$(timeout 5s cartken r ip "$ROBOT" 2>&1) || {
    echo "⚠️  Failed to get IP for $ROBOT"; echo "$IP_OUT"; continue
  }

  echo "[*] IPs for $ROBOT:"
  echo "$IP_OUT"

  ROBOT_IP=""
  while read -r iface ip _; do
    for want in "${INTERFACES[@]}"; do
      [[ "$iface" != "$want" ]] && continue
      echo "→ testing $iface ($ip)…"
      if ping -4 -c1 -W2 "$ip" &>/dev/null; then
        ROBOT_IP="$ip"
        echo "✓ selected $iface ($ip)"
        break 2
      else
        echo "✗ $iface unreachable"
      fi
    done
  done <<< "$IP_OUT"

  if [[ -z "$ROBOT_IP" ]]; then
    echo "❌ no reachable IP for $ROBOT"
    continue
  fi

  # per-robot output dir
  DEST_DIR="$TMP_CRT_DIR/$ROBOT"
  mkdir -p "$DEST_DIR"

  echo "[*] Pulling crts from $ROBOT ($ROBOT_IP)…"
  sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "cartken@$ROBOT_IP:$REMOTE_PATH/robot.crt" "$DEST_DIR/robot.crt"
  sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "cartken@$ROBOT_IP:$REMOTE_PATH/robot.key" "$DEST_DIR/robot.key"
done

echo "✓ All crts saved under ./$TMP_CRT_DIR/"

