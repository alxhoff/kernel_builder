#!/usr/bin/env python3
import argparse
import os
import subprocess
import sys
import re
import time
import threading
from collections import deque

def run_command(command):
    """Runs a shell command and handles errors."""
    try:
        subprocess.run(
            command,
            shell=True,
            check=True,
            text=True,
            stdout=sys.stdout,
            stderr=sys.stderr
        )
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {e}", file=sys.stderr)
        sys.exit(1)

def setup_can(device):
    """Sets up the CAN device with specified parameters."""
    print(f"Setting up CAN device: {device}")
    run_command(f"ip link set down {device}")
    run_command(f"ip link set {device} type can bitrate 500000 restart-ms 1000 sjw 15 dsjw 15 fd on dbitrate 2000000 sample-point 0.8 dsample-point 0.8")
    run_command(f"ip link set up {device}")
    print(f"CAN device {device} is set up.")

def trigger_can(device):
    """Sends a specific CAN frame to the device."""
    print(f"Sending trigger frame to {device}...")
    id_map = {
        "can4": 201,
        "can5": 401,
        "can6": 301,
        "can7": 501,
    }
    can_id = id_map.get(device, 501)
    run_command(f"cansend {device} {can_id}##000.00.00.00.00.00.00.00")
    print("Trigger frame sent.")

def show_errors(device):
    """Shows CAN bus statistics and errors."""
    print(f"--- CAN Bus Statistics and Errors for {device} ---")
    run_command(f"ip -details -statistics link show {device}")

def monitor_traffic(device):
    """Monitors live CAN bus traffic."""
    print(f"Monitoring live CAN traffic on {device} (press Ctrl+C to stop)...")
    try:
        run_command(f"candump {device}")
    except KeyboardInterrupt:
        print("Monitoring stopped.")
        sys.exit(0)

def show_nodes(device):
    """Monitors CAN traffic, prints the message for new node IDs, and lists all unique IDs found."""
    print(f"Monitoring for unique CAN node IDs on {device} (press Ctrl+C to stop)...")

    unique_ids = set()
    process = None
    exit_code = 0

    try:
        process = subprocess.Popen(
            ['candump', device],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            universal_newlines=True
        )

        for line in iter(process.stdout.readline, ''):
            line = line.strip()
            if not line:
                continue

            parts = line.split()
            if len(parts) < 2:
                continue

            can_id = parts[1]

            if can_id not in unique_ids:
                unique_ids.add(can_id)

                print(f"New CAN ID found in message: '{line}'")

                sorted_ids = sorted(list(unique_ids))
                print(f"Unique IDs seen so far ({len(unique_ids)}): {sorted_ids}")
                print("---")

        process.stdout.close()
        stderr_output = process.stderr.read()
        if stderr_output:
            print(f"Error from candump: {stderr_output}", file=sys.stderr)
        process.wait()

    except FileNotFoundError:
        print("Error: 'candump' command not found. Please make sure can-utils is installed.", file=sys.stderr)
        exit_code = 1
    except KeyboardInterrupt:
        print("\nMonitoring stopped.")
    except Exception as e:
        print(f"An error occurred: {e}", file=sys.stderr)
        exit_code = 1
    finally:
        if process and process.poll() is None:
            process.terminate()

    print(f"\nTotal unique CAN IDs found: {len(unique_ids)}")
    sys.exit(exit_code)


def monitor_dmesg(device, verbose=False):
    """Monitors dmesg for tcan4x5x messages for a specific device."""
    print(f"Monitoring dmesg for tcan4x5x messages on {device} (press Ctrl+C to stop)...")

    last_fgi = None
    active_fgi = None
    recent_ids = deque(maxlen=88)

    expected_ids = set()
    collecting_expected_ids = True

    process = None
    exit_code = 0

    try:
        process = subprocess.Popen(
            ['dmesg', '-w'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            universal_newlines=True
        )

        for line in iter(process.stdout.readline, ''):
            line = line.strip()
            if f'tcan4x5x' not in line or f' {device}:' not in line:
                continue

            fgi_match = re.search(r'm_can_read_fifo fgi: (\d+)', line)
            if fgi_match:
                new_fgi = int(fgi_match.group(1))
                active_fgi = new_fgi

                if verbose:
                    # Check for non-sequential FGI. Assuming 32-entry FIFO (0-31).
                    if last_fgi is not None and new_fgi != (last_fgi + 1) % 32:
                        print(f"Warning: FGI jump from {last_fgi} to {new_fgi}")

                last_fgi = new_fgi

                if verbose:
                    print(f"--- FGI batch: {active_fgi} ---")
                continue

            # Don't process any CAN IDs until we've seen our first FGI line
            if active_fgi is None:
                continue

            can_id_match = re.search(r'CAN-FD: id=0x([0-9a-fA-F]+)', line)
            if can_id_match:
                can_id = int(can_id_match.group(1), 16)

                if verbose:
                    print(f"  ID: {can_id:x}")

                recent_ids.append(can_id)

                if collecting_expected_ids:
                    if can_id not in expected_ids:
                        expected_ids.add(can_id)
                        if not verbose:
                            print(f"Collecting expected IDs: {len(expected_ids)}/88 found...", end='\r')
                        else:
                            print(f"  Collected {len(expected_ids)}/88 unique expected IDs.")

                    if len(expected_ids) == 88:
                        collecting_expected_ids = False
                        if not verbose:
                            print() # Newline after progress indicator
                        print("--- All 88 expected IDs collected. Now tracking against this set. ---")
                        if verbose:
                            hex_expected_ids = [f'{i:x}' for i in sorted(list(expected_ids))]
                            print(f"  Expected set: {hex_expected_ids}")

                if not collecting_expected_ids:
                    unique_ids_in_window = set(recent_ids)

                    if len(unique_ids_in_window) < len(recent_ids):
                         print(f"  WARNING: Last {len(recent_ids)} messages contain duplicates. Only {len(unique_ids_in_window)} unique IDs.")

                    missing_ids = expected_ids - unique_ids_in_window

                    if missing_ids:
                        hex_missing_ids = [f'{i:x}' for i in sorted(list(missing_ids))]
                        print(f"  Missing from last {len(recent_ids)} ({len(missing_ids)} from expected set): {hex_missing_ids}")
                    elif verbose:
                        print("  All expected IDs are present in the last 88 messages.")

                    if verbose:
                        print("---")

    except FileNotFoundError:
        print("Error: 'dmesg' command not found.", file=sys.stderr)
        exit_code = 1
    except KeyboardInterrupt:
        print("\nMonitoring stopped.")
    except Exception as e:
        print(f"An error occurred: {e}", file=sys.stderr)
        exit_code = 1
    finally:
        if process and process.poll() is None:
            process.terminate()

    sys.exit(exit_code)






def monitor_interrupts(device):
    """Monitors interrupt events and dmesg fgi changes for the given CAN device."""
    print(f"Monitoring interrupt events and FGI changes for {device} (press Ctrl+C to stop)...")
    print("NOTE: This mode polls at high frequency and will increase CPU usage.")

    # --- Helper for dmesg reading ---
    def dmesg_reader_thread(device, shared_data, lock, stop_event):
        process = None
        try:
            process = subprocess.Popen(
                ['dmesg', '-w'],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
                universal_newlines=True
            )

            while not stop_event.is_set():
                line = process.stdout.readline()
                if not line:
                    break
                line = line.strip()
                if f'tcan4x5x' not in line or f' {device}:' not in line:
                    continue

                fgi_match = re.search(r'm_can_read_fifo fgi: (\d+)', line)
                if fgi_match:
                    current_fgi = int(fgi_match.group(1))
                    with lock:
                        shared_data['latest_fgi'] = current_fgi
                        shared_data['total_fgi_updates'] += 1

        except FileNotFoundError:
            with lock:
                shared_data['error'] = "'dmesg' command not found"
        except Exception as e:
            with lock:
                shared_data['error'] = str(e)
        finally:
            if process:
                process.terminate()

    # --- Find interrupt line logic (as corrected before) ---
    irq_number = None
    try:
        with open(f'/sys/class/net/{device}/device/irq', 'r') as f:
            irq_number = f.read().strip()
    except (FileNotFoundError, IOError):
        print(f"Warning: Could not read IRQ for device {device} via sysfs. Will try to find interrupt by device name in /proc/interrupts.", file=sys.stderr)

    interrupt_line_prefix = None
    if irq_number:
        interrupt_line_prefix = f"{irq_number}:"
        print(f"Found IRQ {irq_number} for device {device}.")
    else:
        print(f"Searching for '{device}' in /proc/interrupts.")
        try:
            with open('/proc/interrupts', 'r') as f:
                for line in f:
                    parts = line.strip().split()
                    if parts and parts[-1] == device:
                        interrupt_line_prefix = parts[0]
                        if not interrupt_line_prefix.endswith(':'):
                            continue
                        print(f"Found interrupt line for {device} with IRQ {interrupt_line_prefix[:-1]}.")
                        break
        except FileNotFoundError:
            print("Error: /proc/interrupts not found.", file=sys.stderr)
            sys.exit(1)

    if not interrupt_line_prefix:
        print(f"Error: Could not find interrupt for {device}.", file=sys.stderr)
        sys.exit(1)

    # --- Threading and main loop setup ---
    shared_data = {'latest_fgi': 'N/A', 'total_fgi_updates': 0, 'error': None}
    lock = threading.Lock()
    stop_event = threading.Event()

    dmesg_thread = threading.Thread(
        target=dmesg_reader_thread,
        args=(device, shared_data, lock, stop_event)
    )
    dmesg_thread.daemon = True
    dmesg_thread.start()

    try:
        # --- Get initial state ---
        initial_count = 0
        try:
            with open('/proc/interrupts', 'r') as f:
                for line in f:
                    if line.strip().startswith(interrupt_line_prefix):
                        parts = [p for p in line.split() if p]
                        counts = [int(p) for p in parts[1:] if p.isdigit()]
                        initial_count = sum(counts)
                        break
        except FileNotFoundError:
            print("Error: /proc/interrupts not found.", file=sys.stderr)
            sys.exit(1)

        last_interrupt_count = initial_count

        with lock:
            fgi_at_last_interrupt = shared_data['total_fgi_updates']

        last_interrupt_time = time.time()

        print("Waiting for first interrupt...")

        while True:
            # --- Poll /proc/interrupts ---
            current_interrupt_count = 0
            found = False
            try:
                with open('/proc/interrupts', 'r') as f:
                    for line in f:
                        if line.strip().startswith(interrupt_line_prefix):
                            parts = [p for p in line.split() if p]
                            counts = [int(p) for p in parts[1:] if p.isdigit()]
                            current_interrupt_count = sum(counts)
                            found = True
                            break
            except FileNotFoundError:
                print("Error: /proc/interrupts not found.", file=sys.stderr)
                sys.exit(1)

            if not found:
                print(f"Error: Interrupt line for {interrupt_line_prefix} disappeared from /proc/interrupts.", file=sys.stderr)
                sys.exit(1)

            if current_interrupt_count > last_interrupt_count:
                current_time = time.time()
                time_since_last = current_time - last_interrupt_time
                interrupts_fired = current_interrupt_count - last_interrupt_count

                with lock:
                    total_fgi = shared_data['total_fgi_updates']
                    latest_fgi = shared_data['latest_fgi']

                fgi_since_last = total_fgi - fgi_at_last_interrupt

                print(f"Time since last: {time_since_last:7.4f}s | FGI changes: {fgi_since_last:3d} | Interrupts: {interrupts_fired:2d} | Last FGI: {str(latest_fgi):>3}")

                # Update state for next iteration
                last_interrupt_time = current_time
                last_interrupt_count = current_interrupt_count
                fgi_at_last_interrupt = total_fgi

            # Check for errors from the dmesg thread
            with lock:
                if shared_data['error']:
                    print(f"\nError in dmesg reader thread: {shared_data['error']}", file=sys.stderr)
                    break

            time.sleep(0.001) # High frequency polling

    except KeyboardInterrupt:
        print("\nMonitoring stopped.")
    except Exception as e:
        print(f"An error occurred: {e}", file=sys.stderr)
    finally:
        stop_event.set()
        dmesg_thread.join(timeout=1)
        sys.exit(0)



def monitor_timing(device):
    """Monitors dmesg for CAN-FD messages and calculates the time between them."""
    print(f"Monitoring dmesg for CAN-FD messages on {device} to calculate timing (press Ctrl+C to stop)...")

    last_timestamp = None
    periods = deque(maxlen=1000)
    process = None
    exit_code = 0

    try:
        process = subprocess.Popen(
            ['dmesg', '-w'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            universal_newlines=True
        )

        for line in iter(process.stdout.readline, ''):
            line = line.strip()
            if f'tcan4x5x' not in line or f' {device}:' not in line or 'CAN-FD: id=' not in line:
                continue

            timestamp_match = re.search(r'^\[\s*(\d+\.\d+)\]', line)
            if timestamp_match:
                current_timestamp = float(timestamp_match.group(1))

                if last_timestamp is not None:
                    period = current_timestamp - last_timestamp
                    periods.append(period)

                    avg_period = sum(periods) / len(periods)
                    min_period = min(periods)
                    max_period = max(periods)

                    print(f"Period: {period:.6f}s | Avg: {avg_period:.6f}s | Min: {min_period:.6f}s | Max: {max_period:.6f}s   ", end='\r')

                last_timestamp = current_timestamp

    except FileNotFoundError:
        print("Error: 'dmesg' command not found.", file=sys.stderr)
        exit_code = 1
    except KeyboardInterrupt:
        print("\nMonitoring stopped.")
        # Print final stats
        if periods:
            avg_period = sum(periods) / len(periods)
            min_period = min(periods)
            max_period = max(periods)
            print(f"\n--- Final Statistics ({len(periods)} samples) ---")
            print(f"Average Period: {avg_period:.6f}s")
            print(f"Min Period:     {min_period:.6f}s")
            print(f"Max Period:     {max_period:.6f}s")

    except Exception as e:
        print(f"An error occurred: {e}", file=sys.stderr)
        exit_code = 1
    finally:
        if process and process.poll() is None:
            process.terminate()

    sys.exit(exit_code)



if __name__ == "__main__":
    if os.geteuid() != 0:
        print("This script must be run as root. Please use sudo.", file=sys.stderr)
        sys.exit(1)

    parser = argparse.ArgumentParser(description="A tool to manage CAN devices.")
    parser.add_argument("--device", type=str, required=True, help="CAN interface name (e.g., can0)")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose output for monitoring modes.")

    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--setup", action="store_true", help="Set up the CAN interface.")
    group.add_argument("--trigger", action="store_true", help="Send a trigger frame.")
    group.add_argument("--monitor", action="store_true", help="Monitor live CAN traffic.")
    group.add_argument("--errors", action="store_true", help="Show CAN bus statistics and errors.")
    group.add_argument("--nodes", action="store_true", help="Show unique CAN node IDs from traffic.")
    group.add_argument("--dmesg", action="store_true", help="Monitor dmesg for tcan4x5x messages.")
    group.add_argument("--interrupt", action="store_true", help="Monitor interrupt and FGI events.")
    group.add_argument("--timing", action="store_true", help="Monitor dmesg for CAN-FD message timing.")

    args = parser.parse_args()

    if args.setup:
        setup_can(args.device)
    elif args.trigger:
        trigger_can(args.device)
    elif args.monitor:
        monitor_traffic(args.device)
    elif args.errors:
        show_errors(args.device)
    elif args.nodes:
        show_nodes(args.device)
    elif args.dmesg:
        monitor_dmesg(args.device, args.verbose)
    elif args.interrupt:
        monitor_interrupts(args.device)
    elif args.timing:
        monitor_timing(args.device)
