#!/usr/bin/env python3

import argparse
import subprocess

# Kernel Debugger Script for managing Jetson device debugging

def install_trace_cmd(device_ip, user, dry_run=False):
    # Install trace-cmd on the target device
    install_command = f"ssh root@{device_ip} 'apt-get update && apt-get install -y trace-cmd'"
    print(f"Installing trace-cmd on the target device: {install_command}")
    if not dry_run:
        subprocess.run(install_command, shell=True, check=True)

def list_kernel_modules(device_ip, user, dry_run=False):
    # List loaded kernel modules on the target device
    list_command = f"ssh {user}@{device_ip} 'lsmod'"
    print(f"Listing loaded kernel modules on the target device: {list_command}")
    if not dry_run:
        subprocess.run(list_command, shell=True, check=True)

def list_tracepoints(device_ip, user, dry_run=False):
    # List available tracepoints on the target device via trace-cmd
    list_tracepoints_command = f"ssh {user}@{device_ip} 'trace-cmd list'"
    print(f"Listing available tracepoints on the target device: {list_tracepoints_command}")
    if not dry_run:
        subprocess.run(list_tracepoints_command, shell=True, check=True)

def start_tracing(device_ip, user, events, dry_run=False):
    # Start tracing specific events on the target device
    start_command = f"ssh {user}@{device_ip} 'echo 1 > /sys/kernel/debug/tracing/tracing_on && echo {events} > /sys/kernel/debug/tracing/set_event'"
    print(f"Starting tracing on the target device: {start_command}")
    if not dry_run:
        subprocess.run(start_command, shell=True, check=True)

def stop_tracing(device_ip, user, dry_run=False):
    # Stop tracing on the target device
    stop_command = f"ssh {user}@{device_ip} 'echo 0 > /sys/kernel/debug/tracing/tracing_on'"
    print(f"Stopping tracing on the target device: {stop_command}")
    if not dry_run:
        subprocess.run(stop_command, shell=True, check=True)

def retrieve_kernel_logs(device_ip, user, destination_path, dry_run=False):
    # Retrieve kernel logs (dmesg) from the target device
    remote_logs = f"{user}@{device_ip}:/var/log/dmesg"
    print(f"Copying kernel logs from the target device to {destination_path}")
    if not dry_run:
        subprocess.run(["scp", remote_logs, destination_path], check=True)

def record_trace(device_ip, user, trace_options, duration=None, dry_run=False):
    # Record events on the target device via trace-cmd
    record_command = f"ssh {user}@{device_ip} 'trace-cmd record {trace_options}"
    if duration:
        record_command += f" -d {duration}"
    record_command += "'"

    print(f"Recording trace on the target device: {record_command}")
    if not dry_run:
        subprocess.run(record_command, shell=True, check=True)

def retrieve_trace_data(device_ip, user, destination_path, dry_run=False):
    # Retrieve the trace.dat file from the target device to the host
    remote_trace_file = f"{user}@{device_ip}:/var/tmp/trace.dat"
    print(f"Copying trace.dat from the target device to {destination_path}")
    if not dry_run:
        subprocess.run(["scp", remote_trace_file, destination_path], check=True)

def report_trace(trace_file_path, output_file, dry_run=False):
    # Generate a report from the trace.dat file
    report_command = f"trace-cmd report {trace_file_path} > {output_file}"
    print(f"Generating trace report: {report_command}")
    if not dry_run:
        subprocess.run(report_command, shell=True, check=True)

def start_tracing_system(device_ip, user, dry_run=False):
    # Start system-wide tracing on the target device
    start_command = f"ssh {user}@{device_ip} 'echo 1 > /sys/kernel/debug/tracing/tracing_on'"
    print(f"Starting system-wide tracing on the target device: {start_command}")
    if not dry_run:
        subprocess.run(start_command, shell=True, check=True)

def stop_tracing_system(device_ip, user, dry_run=False):
    # Stop system-wide tracing on the target device
    stop_command = f"ssh {user}@{device_ip} 'echo 0 > /sys/kernel/debug/tracing/tracing_on'"
    print(f"Stopping system-wide tracing on the target device: {stop_command}")
    if not dry_run:
        subprocess.run(stop_command, shell=True, check=True)

def main():
    parser = argparse.ArgumentParser(description="Kernel Debugger Script for managing Jetson device debugging")
    subparsers = parser.add_subparsers(dest="command")

    # Install trace-cmd command
    install_parser = subparsers.add_parser("install-trace-cmd")
    install_parser.add_argument("--ip", required=True, help="IP address of the target device")
    install_parser.add_argument("--user", required=True, help="Username for accessing the target device")
    install_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')

    # List kernel modules command
    list_modules_parser = subparsers.add_parser("list-modules")
    list_modules_parser.add_argument("--ip", required=True, help="IP address of the target device")
    list_modules_parser.add_argument("--user", required=True, help="Username for accessing the target device")
    list_modules_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')

    # List tracepoints command
    list_tracepoints_parser = subparsers.add_parser("list-tracepoints")
    list_tracepoints_parser.add_argument("--ip", required=True, help="IP address of the target device")
    list_tracepoints_parser.add_argument("--user", required=True, help="Username for accessing the target device")
    list_tracepoints_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')

    # Start tracing command
    start_tracing_parser = subparsers.add_parser("start-tracing")
    start_tracing_parser.add_argument("--ip", required=True, help="IP address of the target device")
    start_tracing_parser.add_argument("--user", required=True, help="Username for accessing the target device")
    start_tracing_parser.add_argument("--events", required=True, help="Events to trace")
    start_tracing_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')

    # Stop tracing command
    stop_tracing_parser = subparsers.add_parser("stop-tracing")
    stop_tracing_parser.add_argument("--ip", required=True, help="IP address of the target device")
    stop_tracing_parser.add_argument("--user", required=True, help="Username for accessing the target device")
    stop_tracing_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')

    # Retrieve kernel logs command
    retrieve_logs_parser = subparsers.add_parser("retrieve-logs")
    retrieve_logs_parser.add_argument("--ip", required=True, help="IP address of the target device")
    retrieve_logs_parser.add_argument("--user", required=True, help="Username for accessing the target device")
    retrieve_logs_parser.add_argument("--destination-path", required=True, help="Local path to save the kernel logs")
    retrieve_logs_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')

    # Record trace command
    record_trace_parser = subparsers.add_parser("record-trace")
    record_trace_parser.add_argument("--ip", required=True, help="IP address of the target device")
    record_trace_parser.add_argument("--user", required=True, help="Username for accessing the target device")
    record_trace_parser.add_argument("--trace-options", required=True, help="Options to pass to trace-cmd record")
    record_trace_parser.add_argument("--duration", type=int, help="Duration to record the trace (seconds)")
    record_trace_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')

    # Retrieve trace data command
    retrieve_parser = subparsers.add_parser("retrieve-trace")
    retrieve_parser.add_argument("--ip", required=True, help="IP address of the target device")
    retrieve_parser.add_argument("--user", required=True, help="Username for accessing the target device")
    retrieve_parser.add_argument("--destination-path", required=True, help="Local path to save the trace data")
    retrieve_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')

    # Report trace command
    report_parser = subparsers.add_parser("report-trace")
    report_parser.add_argument("--trace-file-path", required=True, help="Path to the trace.dat file on the host")
    report_parser.add_argument("--output-file", required=True, help="Output file to save the trace report")
    report_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')

    # Start system tracing command
    start_system_parser = subparsers.add_parser("start-system-tracing")
    start_system_parser.add_argument("--ip", required=True, help="IP address of the target device")
    start_system_parser.add_argument("--user", required=True, help="Username for accessing the target device")
    start_system_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')

    # Stop system tracing command
    stop_system_parser = subparsers.add_parser("stop-system-tracing")
    stop_system_parser.add_argument("--ip", required=True, help="IP address of the target device")
    stop_system_parser.add_argument("--user", required=True, help="Username for accessing the target device")
    stop_system_parser.add_argument('--dry-run', action='store_true', help='Print the commands without executing them')

    args = parser.parse_args()

    # Print help if no command is provided
    if not args.command:
        parser.print_help()
        exit(1)

    if args.command == "install-trace-cmd":
        install_trace_cmd(device_ip=args.ip, user=args.user, dry_run=args.dry_run)
    elif args.command == "list-modules":
        list_kernel_modules(device_ip=args.ip, user=args.user, dry_run=args.dry_run)
    elif args.command == "list-tracepoints":
        list_tracepoints(device_ip=args.ip, user=args.user, dry_run=args.dry_run)
    elif args.command == "start-tracing":
        start_tracing(device_ip=args.ip, user=args.user, events=args.events, dry_run=args.dry_run)
    elif args.command == "stop-tracing":
        stop_tracing(device_ip=args.ip, user=args.user, dry_run=args.dry_run)
    elif args.command == "retrieve-logs":
        retrieve_kernel_logs(device_ip=args.ip, user=args.user, destination_path=args.destination_path, dry_run=args.dry_run)
    elif args.command == "record-trace":
        record_trace(device_ip=args.ip, user=args.user, trace_options=args.trace_options, duration=args.duration, dry_run=args.dry_run)
    elif args.command == "retrieve-trace":
        retrieve_trace_data(device_ip=args.ip, user=args.user, destination_path=args.destination_path, dry_run=args.dry_run)
    elif args.command == "report-trace":
        report_trace(trace_file_path=args.trace_file_path, output_file=args.output_file, dry_run=args.dry_run)
    elif args.command == "start-system-tracing":
        start_tracing_system(device_ip=args.ip, user=args.user, dry_run=args.dry_run)
    elif args.command == "stop-system-tracing":
        stop_tracing_system(device_ip=args.ip, user=args.user, dry_run=args.dry_run)

if __name__ == "__main__":
    main()

