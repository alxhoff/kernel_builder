#!/usr/bin/env bash
#
# generate_load_const.sh
#
# Generates a steady, fine-grained CPU load on a Jetson Orin AGX Dev Kit,
# and sets the Orin to a chosen power profile (nvpmodel mode). Uses a small
# C helper that busy-waits in a tight loop for a constant load fraction.
#
# Usage:
#   sudo ./generate_load_const.sh [OPTIONS]
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
#     Mode 0: EDP (MAXN) – all 12 Carmel cores + GPU/DLA/PVA at max clocks
#     Mode 1: 15W    – 4 cores online, CPU ~1.1136GHz, GPU ~420.75MHz, etc.
#     Mode 2: 30W    – 8 cores online, CPU ~1.728GHz, GPU ~624.75MHz, etc.
#     Mode 3: 50W    – 12 cores online, CPU ~1.4976GHz, GPU ~828.75MHz, etc.
#
# Example:
#   # build + stress all cores at 50% for 60s, max-performance (mode 0)
#   sudo ./generate_load_const.sh --all-cores --load 50 --duration 60 --mode 0
#

set -e

print_help() {
  grep '^#' "$0" | sed 's/^# \?//'
  exit 0
}

# Check for required commands
command -v nvpmodel >/dev/null 2>&1 || { echo "Error: nvpmodel not found. Install NVIDIA Jetson Power Management tools."; exit 1; }
command -v jetson_clocks >/dev/null 2>&1 || { echo "Error: jetson_clocks not found. Install NVIDIA Jetson Utilities."; exit 1; }
command -v gcc >/dev/null 2>&1 || { echo "Error: gcc not found. Install build-essential."; exit 1; }

# Paths
BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
BINARY="${BASEDIR}/cpuload_const"

# Build the C helper if missing or outdated
if [[ ! -x "$BINARY" ]]; then
  cat > "${BASEDIR}/cpuload_const.c" << 'EOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <time.h>
#include <unistd.h>
#include <sched.h>
#include <signal.h>

volatile int keep_running = 1;
typedef struct { int core; double load; } thread_arg;

void int_handler(int _) {
    keep_running = 0;
}

void* load_thread(void* arg) {
    thread_arg* t = (thread_arg*)arg;
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(t->core, &cpuset);
    pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);

    const long interval_ns = 10000000; // base interval = 10 ms
    long work_ns = (long)(interval_ns * t->load);
    long sleep_ns = interval_ns - work_ns;

    struct timespec ts_sleep = { .tv_sec = sleep_ns / 1000000000, .tv_nsec = sleep_ns % 1000000000 };
    struct timespec t_start, t_now;
    long elapsed_ns;

    while (keep_running) {
        // Busy-wait (work period)
        clock_gettime(CLOCK_MONOTONIC, &t_start);
        do {
            clock_gettime(CLOCK_MONOTONIC, &t_now);
            elapsed_ns = (t_now.tv_sec - t_start.tv_sec) * 1000000000L
                       + (t_now.tv_nsec - t_start.tv_nsec);
        } while (keep_running && elapsed_ns < work_ns);

        // Sleep for remainder (idle period)
        if (sleep_ns > 0) {
            nanosleep(&ts_sleep, NULL);
        }
    }
    return NULL;
}

int main(int argc, char** argv) {
    if (argc != 4) {
        fprintf(stderr, "Usage: %s <percent_load> <duration_s> <num_cores>\n", argv[0]);
        return 1;
    }
    double pct = atof(argv[1]);
    int dur = atoi(argv[2]);
    int ncores = atoi(argv[3]);
    if (pct < 0 || pct > 100) {
        fprintf(stderr, "Error: load must be 0–100\n");
        return 1;
    }
    double load = pct / 100.0;
    signal(SIGINT, int_handler);

    pthread_t threads[ncores];
    thread_arg args[ncores];
    for (int i = 0; i < ncores; i++) {
        args[i].core = i;
        args[i].load = load;
        pthread_create(&threads[i], NULL, load_thread, &args[i]);
    }
    sleep(dur);
    keep_running = 0;
    for (int i = 0; i < ncores; i++) {
        pthread_join(threads[i], NULL);
    }
    return 0;
}
EOF
  echo "Compiling cpuload_const.c..."
  gcc -O2 -pthread "${BASEDIR}/cpuload_const.c" -o "$BINARY"
  rm "${BASEDIR}/cpuload_const.c"
fi

# Default values
NVP_MODE=0
ALL_CORES=0
CORES=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -l|--load)
      PLOAD="$2"; shift 2
      ;;
    -d|--duration)
      DURATION="$2"; shift 2
      ;;
    -c|--cores)
      CORES="$2"; shift 2
      ;;
    --all-cores)
      ALL_CORES=1; shift
      ;;
    -m|--mode)
      NVP_MODE="$2"; shift 2
      ;;
    -h|--help)
      print_help
      ;;
    *)
      echo "Unknown option: $1"; print_help
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
  MAX=$(nproc)
  if ! [[ "$CORES" =~ ^[0-9]+$ ]] || (( CORES < 1 || CORES > MAX )); then
    echo "Error: --cores must be an integer between 1 and ${MAX}."
    exit 1
  fi
fi

# Apply power profile
echo "Setting nvpmodel to mode ${NVP_MODE}..."
nvpmodel -m "${NVP_MODE}"

# Lock maximum clocks
echo "Applying max clocks (jetson_clocks)..."
jetson_clocks

echo "Running constant load: ${CORES} core(s) at ${PLOAD}% for ${DURATION}s..."
"$BINARY" "$PLOAD" "$DURATION" "$CORES"

echo "Load complete."

