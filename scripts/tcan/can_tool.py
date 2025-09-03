#!/usr/bin/env python3
import argparse
import os
import subprocess
import sys

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
    run_command(f"cansend {device} 501##000.00.00.00.00.00.00.00")
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


if __name__ == "__main__":
    if os.geteuid() != 0:
        print("This script must be run as root. Please use sudo.", file=sys.stderr)
        sys.exit(1)

    parser = argparse.ArgumentParser(description="A tool to manage CAN devices.")
    parser.add_argument("--device", type=str, required=True, help="CAN interface name (e.g., can0)")

    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--setup", action="store_true", help="Set up the CAN interface.")
    group.add_argument("--trigger", action="store_true", help="Send a trigger frame.")
    group.add_argument("--monitor", action="store_true", help="Monitor live CAN traffic.")
    group.add_argument("--errors", action="store_true", help="Show CAN bus statistics and errors.")
    group.add_argument("--nodes", action="store_true", help="Show unique CAN node IDs from traffic.")

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
