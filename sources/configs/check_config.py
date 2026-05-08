#!/usr/bin/env python3
import argparse
import re
import shutil

def parse_config_file(path):
    config = {}
    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('#') and 'is not set' in line:
                match = re.match(r'# (CONFIG_[\w\d_]+) is not set', line)
                if match:
                    config[match.group(1)] = 'not set'
            elif line.startswith('CONFIG_') and '=' in line:
                k, v = line.split('=', 1)
                config[k.strip()] = v.strip()
    return config

def load_lines(path):
    with open(path, 'r') as f:
        return f.readlines()

def write_lines(path, lines):
    with open(path, 'w') as f:
        f.writelines(lines)

def patch_config_lines(original_lines, expected):
    patched = []
    seen = set()
    for line in original_lines:
        match = re.match(r'(CONFIG_[\w\d_]+)(=(.+)| is not set)', line.strip())
        if match:
            key = match.group(1)
            if key in expected:
                new_val = expected[key]
                if new_val == 'not set':
                    patched.append(f"# {key} is not set\n")
                else:
                    patched.append(f"{key}={new_val}\n")
                seen.add(key)
            else:
                patched.append(line)
        else:
            patched.append(line)

    for key, val in expected.items():
        if key not in seen:
            if val == 'not set':
                patched.append(f"# {key} is not set\n")
            else:
                patched.append(f"{key}={val}\n")

    return patched

def main():
    parser = argparse.ArgumentParser(description="Compare and optionally patch a kernel .config file.")
    parser.add_argument("--config", required=True, help="Path to the kernel .config file to patch")
    parser.add_argument("--config-list", required=True, nargs='+', help="Files containing required CONFIG_ entries")
    parser.add_argument("--output", help="Optional output file. If omitted, --config is modified in-place with a .bak backup")
    args = parser.parse_args()

    output_path = args.output if args.output else args.config
    if not args.output:
        backup_path = args.config + ".bak"
        shutil.copy2(args.config, backup_path)
        print(f"📦 Backup created: {backup_path}")

    current_config = parse_config_file(args.config)
    expected_config = {}
    for path in args.config_list:
        expected_config.update(parse_config_file(path))

    for key, expected_val in expected_config.items():
        actual_val = current_config.get(key)
        if actual_val is None:
            print(f"[ADD] {key} = {expected_val}")
        elif actual_val != expected_val:
            print(f"[MOD] {key}: {actual_val} → {expected_val}")

    original_lines = load_lines(args.config)
    new_lines = patch_config_lines(original_lines, expected_config)
    write_lines(output_path, new_lines)
    print(f"\n✅ Patched config written to: {output_path}")

if __name__ == "__main__":
    main()

