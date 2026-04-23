#!/bin/bash

set -e

TRACE_DIR="/sys/kernel/debug/tracing"
TRACE_PIPE="$TRACE_DIR/trace_pipe"
KPROBE_EVENTS="$TRACE_DIR/kprobe_events"

echo "=== RealSense V4L2 Kernel Tracing Setup ==="

# Reset state
echo "[*] Resetting trace buffer and existing probes..."
if [ -e "$TRACE_DIR/events/kprobes/enable" ]; then
    echo 0 > "$TRACE_DIR/events/kprobes/enable" || echo "[!] Couldn't disable kprobe events"
fi
echo > "$TRACE_DIR/trace"
echo > "$KPROBE_EVENTS" 2>/dev/null || echo "[!] Warning: could not clear kprobe_events"

# Register kprobes
echo "[*] Registering kprobes:"

# Special handling for ds5_dfu_device_release with module name
if grep -q 'ds5_dfu_device_release \[d4xx\]' "$TRACE_DIR/available_filter_functions"; then
    echo -n "  [+] Registering probe: ds5_dfu_device_release"
    echo 'p:dfu_release ds5_dfu_device_release' > "$KPROBE_EVENTS" 2>/dev/null \
        && echo " ✔" || echo " ✗ (Failed)"
else
    echo "  [!] Skipping ds5_dfu_device_release — not found in available_filter_functions"
fi

# Generic function probes
PROBES=(
  "video_ioctl2"
  "v4l2_ioctl"
  "v4l_s_ext_ctrls"
  "v4l_g_ext_ctrls"
)

for func in "${PROBES[@]}"; do
    echo -n "  [+] Registering probe: $func"
    if grep -qw "$func" /proc/kallsyms; then
        echo "p:$func $func" >> "$KPROBE_EVENTS" 2>/dev/null \
            && echo " ✔" || echo " ✗ (Invalid argument)"
    else
        echo " ✗ (Not found in /proc/kallsyms)"
    fi
done

# Enable kprobes events
echo "[*] Enabling kprobe event tracing..."
for event in $(find "$TRACE_DIR/events/kprobes" -name enable 2>/dev/null); do
    echo 1 > "$event" || echo "[!] Could not enable: $event"
done

# Enable kernel stack traces for each event
if [ -e "$TRACE_DIR/options/stacktrace" ]; then
    echo "[*] Enabling stack traces for kprobes..."
    echo 1 > "$TRACE_DIR/options/stacktrace"
else
    echo "[!] Stack trace option not available — skipping"
fi

echo 1 > "$TRACE_DIR/tracing_on"

# Capture currently running processes seen in trace (before they can exit)
set +e
echo "[*] Capturing PIDs during trace..."
declare -A PROC_MAP
for pid in $(ls /proc | grep '^[0-9]\+$'); do
    exe=$(readlink -f /proc/$pid/exe 2>/dev/null || true)
    [ -n "$exe" ] && PROC_MAP["$pid"]="$exe"
done
set -e

echo ""
echo "[*] Tracing is now live. Collecting for 2 seconds..."
echo "------------------------------------------------------------"

TRACE_OUT="v4l.trace"
# Capture trace for 2 seconds
timeout 2s cat "$TRACE_PIPE" | tee "$TRACE_OUT"

echo "------------------------------------------------------------"

# Print involved processes and executables
echo ""
echo "[*] Processes seen in trace:"
awk '{ print $1 }' "$TRACE_OUT" | grep -E '^[a-zA-Z0-9_-]+-[0-9]+$' | sort -u | while read proc; do
    pid=$(echo "$proc" | awk -F'-' '{ print $NF }')
    exe_host=$(readlink -f /proc/"$pid"/exe 2>/dev/null || echo "?")

    # Try resolving from inside Docker
    container_exe=$(docker exec kernel_devel sh -c "cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' '")
    [ -z "$container_exe" ] && container_exe="–"

    printf "    - %-20s -> host: %s | docker: %s\n" "$proc" "$exe_host" "$container_exe"
done

echo "[*] Done."

