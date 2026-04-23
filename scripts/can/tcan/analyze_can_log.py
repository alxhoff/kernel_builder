#!/usr/bin/env python3
"""Analyze CAN log files for radar cycle completeness on one or more channels."""
import argparse
import re
import sys

# Base ID for the start of a cycle (Locations 0-2).
START_ID = 0x18FF04B0
# ID for the end of a cycle (Locations 252-254).
END_ID = 0x18FF58B0
# Increment between message IDs.
ID_STEP = 0x100
# Total expected messages per cycle (0x04B0 to 0x58B0 inclusive).
EXPECTED_COUNT = 85


def get_expected_ids():
    """Generate the set of all 85 expected CAN IDs in a cycle."""
    ids = set()
    curr = START_ID
    while curr <= END_ID:
        ids.add(curr)
        curr += ID_STEP
    return ids


def analyze_channel(channel_name, lines, label_prefix=True):
    """Analyze log lines for a specific CAN channel and print a report."""
    id_regex = re.compile(
        r"^\s*" + re.escape(channel_name) + r"\s+([0-9A-Fa-f]{8})\s+\[\d+\]"
    )

    expected_ids = get_expected_ids()
    cycles = []
    current_cycle = []

    if label_prefix:
        print(f"\n--- Analyzing {channel_name} ---")

    for i, line in enumerate(lines):
        match = id_regex.match(line)
        if not match:
            continue

        msg_id_val = int(match.group(1), 16)
        if msg_id_val in expected_ids:
            current_cycle.append({"line": i + 1, "id": msg_id_val})
            if msg_id_val == END_ID:
                cycles.append(current_cycle)
                current_cycle = []

    if current_cycle:
        cycles.append(current_cycle)

    valid_cycles = 0
    partial_cycles = 0
    broken_cycles = 0

    if not cycles:
        print(f"No radar cycles found on {channel_name}.")
        return

    for i, cycle in enumerate(cycles):
        cycle_ids = {msg["id"] for msg in cycle}
        is_start_present = START_ID in cycle_ids
        is_end_present = END_ID in cycle_ids
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

        print(f"Cycle {i + 1}: {status}")
        print(f"  Range: Line {cycle[0]['line']} -> {cycle[-1]['line']}")
        print(f"  Count: {len(cycle)} / {EXPECTED_COUNT} messages")

        if status == "BROKEN (Packet Loss)":
            print(f"  !! MISSING {len(missing)} MESSAGES !!")
            missing_list = sorted(list(missing))
            print(f"  Example Missing IDs: {[hex(x) for x in missing_list[:5]]}...")

        if status != "COMPLETE":
            print("-" * 40)

    summary_label = f" for {channel_name}" if label_prefix else ""
    print(f"\nSummary{summary_label}:")
    print(f"  Total Cycles Detected: {len(cycles)}")
    print(f"  Perfect Cycles:        {valid_cycles}")
    print(f"  Broken Cycles (Loss):  {broken_cycles}")
    print(f"  Partial Cycles:        {partial_cycles}")


def analyze_log(log_file, interfaces):
    try:
        with open(log_file, "r") as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"Error: Log file not found at {log_file}")
        sys.exit(1)

    print(f"Loaded {len(lines)} lines from {log_file}")
    print(
        f"Expected Cycle: {EXPECTED_COUNT} messages "
        f"(ID range {START_ID:X} -> {END_ID:X})"
    )

    multi = len(interfaces) > 1
    for channel in interfaces:
        analyze_channel(channel, lines, label_prefix=multi)


def main():
    parser = argparse.ArgumentParser(
        description="Analyze CAN log files for radar cycle completeness."
    )
    parser.add_argument("log_file", help="Path to the CAN log file")
    parser.add_argument(
        "--interfaces",
        default="can0",
        help=(
            "Comma-separated list of CAN interfaces to analyze "
            "(default: can0). Example: --interfaces can0,can1"
        ),
    )
    args = parser.parse_args()

    interfaces = [x.strip() for x in args.interfaces.split(",") if x.strip()]
    if not interfaces:
        parser.error("--interfaces must not be empty")

    analyze_log(args.log_file, interfaces)


if __name__ == "__main__":
    main()
