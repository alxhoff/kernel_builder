#!/usr/bin/env python3
import re
import sys

# --- Radar Constants ---
# Base ID for the start of a cycle (Locations 0-2)
START_ID = 0x18FF04B0
# ID for the end of a cycle (Locations 252-254)
END_ID = 0x18FF58B0
# The increment between message IDs
ID_STEP = 0x100
# Total expected messages per cycle (0x04B0 to 0x58B0 inclusive)
EXPECTED_COUNT = 85

def get_expected_ids():
    """Generates the set of all 85 expected CAN IDs in a cycle."""
    ids = set()
    curr = START_ID
    while curr <= END_ID:
        ids.add(curr)
        curr += ID_STEP
    return ids

def analyze_channel(channel_name, lines):
    """Analyzes log lines for a specific CAN channel."""

    # Regex to parse 'canX 18FF04B0 ...' lines
    # Matches hex ID (extended)
    # Note: This regex is specific to the requested channel
    id_regex = re.compile(r"^\s*" + re.escape(channel_name) + r"\s+([0-9A-Fa-f]{8})\s+\[\d+\]")

    expected_ids = get_expected_ids()
    cycles = []
    current_cycle = []

    print(f"\n--- Analyzing {channel_name} ---")

    # Pass 1: Group messages into cycles
    for i, line in enumerate(lines):
        match = id_regex.match(line)
        if not match:
            continue

        msg_id_val = int(match.group(1), 16)

        # Only track IDs that belong to our radar range
        if msg_id_val in expected_ids:
            current_cycle.append({
                'line': i + 1,
                'id': msg_id_val
            })

            if msg_id_val == END_ID:
                # End of cycle detected. Archive it and start new.
                cycles.append(current_cycle)
                current_cycle = []

    # Handle the trailing partial cycle (if any)
    if current_cycle:
        cycles.append(current_cycle)

    # Pass 2: Analyze each cycle
    valid_cycles = 0
    partial_cycles = 0
    broken_cycles = 0

    if not cycles:
        print(f"No radar cycles found on {channel_name}.")
        return

    for i, cycle in enumerate(cycles):
        cycle_ids = {msg['id'] for msg in cycle}
        is_start_present = START_ID in cycle_ids
        is_end_present = END_ID in cycle_ids

        # Determine cycle status
        status = "UNKNOWN"
        missing = expected_ids - cycle_ids

        if is_start_present and is_end_present:
            if len(missing) == 0:
                status = "COMPLETE"
                valid_cycles += 1
            else:
                status = "BROKEN (Packet Loss)"
                broken_cycles += 1
        elif not is_start_present and is_end_present:
             status = "PARTIAL (Start Missing - Likely Log Start)"
             partial_cycles += 1
        elif is_start_present and not is_end_present:
             status = "PARTIAL (End Missing - Likely Log End)"
             partial_cycles += 1
        else:
             status = "FRAGMENT (No Start/End Marker)"
             partial_cycles += 1

        # Report
        print(f"Cycle {i+1}: {status}")
        print(f"  Range: Line {cycle[0]['line']} -> {cycle[-1]['line']}")
        print(f"  Count: {len(cycle)} / {EXPECTED_COUNT} messages")

        if status == "BROKEN (Packet Loss)":
            print(f"  !! MISSING {len(missing)} MESSAGES !!")
            # Print the first few missing IDs to help debug
            missing_list = sorted(list(missing))
            print(f"  Example Missing IDs: {[hex(x) for x in missing_list[:5]]}...")

        # Optional: reduce verbosity for perfect cycles
        if status != "COMPLETE":
            print("-" * 40)

    print(f"\nSummary for {channel_name}:")
    print(f"  Total Cycles Detected: {len(cycles)}")
    print(f"  Perfect Cycles:        {valid_cycles}")
    print(f"  Broken Cycles (Loss):  {broken_cycles}")
    print(f"  Partial Cycles:        {partial_cycles}")

def analyze_log(log_file):
    try:
        with open(log_file, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"Error: Log file not found at {log_file}")
        sys.exit(1)

    print(f"Loaded {len(lines)} lines from {log_file}")

    # Analyze can0
    analyze_channel("can0", lines)

    # Analyze can1
    analyze_channel("can1", lines)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: ./analyze_dual_can_log.py <path_to_log_file>")
        sys.exit(1)

    analyze_log(sys.argv[1])
