#!/usr/bin/env bash
#
# generate_load.sh
#
# Generates an even CPU load across specified cores on a Jetson Orin AGX Dev Kit,
# and sets the Orin to a chosen power profile (nvpmodel mode).
#
# Usage:
#   sudo ./generate_load.sh [OPTIONS]
#
# Options:
#   -l, --load <percent>         Percentage load per core (0–100) (required)
#   -d, --duration <seconds>     Duration in seconds for the load (required)
#   -c, --cores <number>         Number of CPU cores to stress (default: all)
#       --all-cores              Stress every available logical core
#   -m, --mode <nvpmodel_mode>   nvpmodel mode integer (default: 0 = EDP/max-performance)
#   -h, --help                   Show this help message and exit
#
# Orin AGX Power profiles (nvpmodel modes):
#   Run `nvpmodel -q` on your Orin AGX to verify exact mappings, but commonly:
#
#   Mode 0: EDP (MAXN) – no enforced power limit; all 12 Carmel cores + GPU/DLA/PVA at max frequencies
#   Mode 1: 15W    – “15W” power budget; only 4 cores online, CPU max ~1.1136 GHz, GPU ~420.75 MHz, DLA ~1369.6 MHz, PVA 1 core @ 307.2 MHz
#   Mode 2: 30W    – “30W” power budget; 8 cores online, CPU max ~1.728 GHz, GPU ~624.75 MHz, DLA ~750 MHz, PVA 1 core @ 512 MHz
#   Mode 3: 50W    – “50W” power budget; all 12 cores online, CPU max ~1.4976 GHz, GPU ~828.75 MHz, DLA ~1369.6 MHz, PVA 1 core @ 704 MHz
#
# Examples:
#   # 1) Stress all 12 cores at 50% for 60 s, EDP (mode 0):
#   sudo ./generate_load.sh --all-cores --load 50 --duration 60 --mode 0
#
#   # 2) Stress 4 cores at 75% for 120 s, 15W mode (mode 1):
#   sudo ./generate_load.sh -c 4 -l 75 -d 120 -m 1
#
#   # 3) Stress all cores at 100% for 30 s, 30W mode (mode 2):
#   sudo ./generate_load.sh --all-cores --load 100 --duration 30 --mode 2
#

set -e

print_help() {
  grep '^#' "$0" | sed 's/^# \?//'
  exit 0
}

# Check for required commands
command -v nvpmodel >/dev/null 2>&1 || { echo "Error: nvpmodel not found. Install NVIDIA Jetson Power Management tools."; exit 1; }
command -v jetson_clocks >/dev/null 2>&1 || { echo "Error: jetson_clocks not found. Install NVIDIA Jetson Utilities."; exit 1; }
if ! command -v stress-ng >/dev/null 2>&1; then
  echo "Installing stress-ng..."
  apt-get update && apt-get install -y stress-ng
fi

# Default values
NVP_MODE=0
ALL_CORES=0
CORES=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -l|--load)
      PLOAD="$2"
      shift 2
      ;;
    -d|--duration)
      DURATION="$2"
      shift 2
      ;;
    -c|--cores)
      CORES="$2"
      shift 2
      ;;
    --all-cores)
      ALL_CORES=1
      shift
      ;;
    -m|--mode)
      NVP_MODE="$2"
      shift 2
      ;;
    -h|--help)
      print_help
      ;;
    *)
      echo "Unknown option: $1"
      print_help
      ;;
  esac
done

# Check mandatory parameters
if [[ -z "$PLOAD" || -z "$DURATION" ]]; then
  echo "Error: --load and --duration are required."
  print_help
fi

# Validate load percentage
if (( PLOAD < 0 || PLOAD > 100 )); then
  echo "Error: --load must be between 0 and 100."
  exit 1
fi

# Determine cores to use
if (( ALL_CORES == 1 )); then
  CORES=$(nproc)
elif [[ -z "$CORES" ]]; then
  CORES=$(nproc)
else
  MAX_CORES=$(nproc)
  if ! [[ "$CORES" =~ ^[0-9]+$ ]] || (( CORES < 1 || CORES > MAX_CORES )); then
    echo "Error: --cores must be an integer between 1 and ${MAX_CORES}."
    exit 1
  fi
fi

# Apply power profile
echo "Setting nvpmodel to mode ${NVP_MODE}..."
nvpmodel -m "${NVP_MODE}"

# Lock maximum clocks
echo "Applying max clocks (jetson_clocks)..."
jetson_clocks

echo "Stressing ${CORES} core(s) at ${PLOAD}% load for ${DURATION}s..."
stress-ng --cpu "$CORES" \
          --cpu-load "$PLOAD" \
          --timeout "${DURATION}s" \
          --metrics-brief

echo "Load complete."

