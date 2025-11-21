#!/usr/bin/python3
import re
import sys

SET1_IDS = {
    '204', '205', '208', '209', '20A', '20B', '20C', '20D', '20E', '20F', '210', '211', '212', '213', '214',
    '215', '216', '217', '218', '219', '21A', '21B', '21C', '21D', '21E', '21F', '220', '221', '222', '223', '224',
    '225', '226', '227', '228', '229', '22A', '22B', '22C', '22D', '22E', '22F', '230', '231', '232', '233', '234',
    '235', '236', '237', '238', '239', '23A', '23B', '23C', '23D', '23E', '23F', '240', '241', '242', '243', '244',
    '245', '246', '247', '248', '249', '24A', '24B', '24C', '24D', '24E', '24F', '250', '251', '252', '253', '254',
    '255', '256', '257', '258', '259', '25A', '25B', '25C'
}
SET2_IDS = {
    '404', '405', '408', '409', '40A', '40B', '40C', '40D', '40E', '40F', '410', '411', '412', '413', '414',
    '415', '416', '417', '418', '419', '41A', '41B', '41C', '41D', '41E', '41F', '420', '421', '422', '423', '424',
    '425', '426', '427', '428', '429', '42A', '42B', '42C', '42D', '42E', '42F', '430', '431', '432', '433', '434',
    '435', '436', '437', '438', '439', '43A', '43B', '43C', '43D', '43E', '43F', '440', '441', '442', '443', '444',
    '445', '446', '447', '448', '449', '44A', '44B', '44C', '44D', '44E', '44F', '450', '451', '452', '453', '454',
    '455', '456', '457', '458', '459', '45A', '45B', '45C'
}

def analyze_log(log_file):
    """
    Analyzes a CAN log file for missing messages in predefined sets.
    - A cycle is defined as the messages between two consecutive start IDs
      ('204' for set 1, '404' for set 2).
    - When a new cycle starts, the previous one is analyzed to see which IDs
      from the set were not present.
    - An ID of '000' invalidates the current cycle, and it's reported as broken.
    - IDs '022' and '024' are ignored.
    - The analysis ignores the first and last detected cycles.
    """
    try:
        with open(log_file, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"Error: Log file not found at {log_file}")
        sys.exit(1)

    id_regex = re.compile(r"^\s*can\d\s+([0-9A-Fa-f]+)\s+\[\d+\]")
    all_results = []

    # State for Set 1
    s1_active = False
    s1_start_line = 0
    s1_bucket = set()

    # State for Set 2
    s2_active = False
    s2_start_line = 0
    s2_bucket = set()

    for i, line in enumerate(lines):
        line_num = i + 1
        match = id_regex.match(line)
        if not match:
            continue

        msg_id = match.group(1).upper()

        if msg_id == '000':
            if s1_active:
                missing = sorted(list(SET1_IDS - s1_bucket))
                all_results.append({'set': 1, 'start': s1_start_line, 'end': line_num, 'missing': missing, 'reason': 'Interrupted by 000 ID'})
                s1_active = False
            if s2_active:
                missing = sorted(list(SET2_IDS - s2_bucket))
                all_results.append({'set': 2, 'start': s2_start_line, 'end': line_num, 'missing': missing, 'reason': 'Interrupted by 000 ID'})
                s2_active = False
            continue

        if msg_id in ('022', '024'):
            continue

        # --- Set 1 Logic ---
        if msg_id == '204':
            if s1_active:
                missing_ids = SET1_IDS - s1_bucket
                all_results.append({'set': 1, 'start': s1_start_line, 'end': line_num - 1, 'missing': sorted(list(missing_ids))})
            s1_active = True
            s1_start_line = line_num
            s1_bucket = {'204'}
        elif msg_id in SET1_IDS and s1_active:
            s1_bucket.add(msg_id)

        # --- Set 2 Logic ---
        if msg_id == '404':
            if s2_active:
                missing_ids = SET2_IDS - s2_bucket
                all_results.append({'set': 2, 'start': s2_start_line, 'end': line_num - 1, 'missing': sorted(list(missing_ids))})
            s2_active = True
            s2_start_line = line_num
            s2_bucket = {'404'}
        elif msg_id in SET2_IDS and s2_active:
            s2_bucket.add(msg_id)

    # The last active cycle is ignored by default as it's incomplete.

    if len(all_results) < 3:
        print("Fewer than 3 cycles were detected, so no analysis can be provided.")
        print(f"(Found {len(all_results)} cycles total).")
        return

    all_results.sort(key=lambda c: c['start'])
    analysis_cycles = all_results[1:-1]

    if not analysis_cycles:
        print("Not enough cycles to analyze after ignoring the first and last.")
        return

    total_missing = 0
    print("--- CAN Log Analysis ---")
    for cycle in analysis_cycles:
        missing_count = len(cycle['missing'])
        total_missing += missing_count
        print(f"Cycle for set {cycle['set']} (lines {cycle['start']}-{cycle['end']})")
        print(f"  Missing messages: {missing_count}")
        if missing_count > 0:
            print(f"  Missing IDs: {cycle['missing']}")
        print("---")

    average_missing = total_missing / len(analysis_cycles)
    print("\n--- Summary ---")
    print(f"Analyzed {len(analysis_cycles)} cycles (ignored first and last).")
    print(f"Average missing messages per cycle: {average_missing:.2f}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python analyze_can_log.py <path_to_log_file>")
        sys.exit(1)
    analyze_log(sys.argv[1])