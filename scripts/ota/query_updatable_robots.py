#!/usr/bin/env python3

#!/usr/bin/env python3

import argparse
import re
import socket
import subprocess
import sys

from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Lock

try:
    import paramiko
except ImportError:
    print("paramiko not found. Installing...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "paramiko"])
    import paramiko

def get_robot_ips(robot_num):
    print(f"  → Fetching IPs using: cartken r ip {robot_num}")
    try:
        result = subprocess.run(
            ["cartken", "r", "ip", str(robot_num)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        output = result.stdout + result.stderr
        print(f"    ↪ Raw IP output:\n{output.strip()}")
        lines = output.strip().splitlines()
        ip_map = {}

        for line in lines[1:]:  # Skip "IPs of robot 'X':"
            parts = line.split()
            if len(parts) == 2:
                iface, ip = parts
                ip_map[iface] = ip
        return ip_map
    except Exception as e:
        print(f"    ❌ Error getting IPs for robot {robot_num}: {e}")
        return {}

def try_ssh_and_check(ip, password):
    print(f"    → Trying SSH to {ip}")
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(ip, username="cartken", password=password, timeout=5)

        cmd = f"echo {password} | sudo -S nvbootctrl dump-slots-info"
        stdin, stdout, stderr = client.exec_command(cmd)
        output = stdout.read().decode()
        print(f"    ↪ SSH success. Raw output:\n{output.strip()}")
        client.close()

        match = re.search(r"Current version:\s*(\S+)", output)
        if not match:
            print("    ⚠️  Couldn't parse version from output.")
            return "error"
        version = match.group(1)
        print(f"    ✅ Parsed version: {version}")
        return "needs updating" if version == "0.0.1" else "updated"

    except Exception as e:
        print(f"    ❌ SSH error to {ip}: {e}")
        return "unreachable"

def main():
    parser = argparse.ArgumentParser(description="Probe robots for bootloader version.")
    parser.add_argument("--password", required=True, help="Password for SSH and sudo")
    parser.add_argument("--starting-index", type=int, default=307, help="Start of robot range")
    parser.add_argument("--finishing-index", type=int, default=383, help="End of robot range")

    args = parser.parse_args()

    from concurrent.futures import ThreadPoolExecutor, as_completed
    from threading import Lock
    import csv

    results = {
        "needs updating": [],
        "updated": [],
        "unreachable": []
    }

    lock = Lock()

    def probe_robot(robot_num, password):
        print(f"\n=== Probing robot {robot_num} ===")
        ip_map = get_robot_ips(robot_num)
        if not ip_map:
            print("    ❌ No IPs found.")
            return robot_num, "unreachable"

        for iface in ["wlan0", "modem1", "modem2", "modem3"]:
            ip = ip_map.get(iface)
            if ip:
                status = try_ssh_and_check(ip, password)
                if status != "unreachable" and status != "error":
                    print(f"    ✅ Robot {robot_num} is {status} via {iface}")
                    return robot_num, status
        print("    ❌ All IPs unreachable.")
        return robot_num, "unreachable"

    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = {
            executor.submit(probe_robot, robot_num, args.password): robot_num
            for robot_num in range(args.starting_index, args.finishing_index + 1)
        }

        for future in as_completed(futures):
            robot_num, status = future.result()
            with lock:
                results[status].append(robot_num)

    # Pretty summary
    print("\n" + "="*40)
    print("📋 Summary".center(40))
    print("="*40)

    for category, label, icon in [
        ("needs updating", "Needs Updating", "🛠️ "),
        ("updated",        "Up-to-date",     "✅ "),
        ("unreachable",    "Unreachable",    "❌ "),
    ]:
        robots = sorted(results[category])
        print(f"{icon} {label:<15} ({len(robots):>2}) : {', '.join(str(r) for r in robots) if robots else '—'}")

    # CSV export
    csv_path = "robot_probe_results.csv"
    with open(csv_path, mode="w", newline="") as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(["Robot Number", "Status"])
        for status in ["needs updating", "updated", "unreachable"]:
            for robot in sorted(results[status]):
                writer.writerow([robot, status])
    print(f"\n📝 Results saved to {csv_path}")


if __name__ == "__main__":
    main()

