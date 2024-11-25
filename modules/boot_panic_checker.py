#!/usr/bin/env python3

import os

def viki_code():
    print("Running VIKI code...")

def check_and_handle_panic_log():
    panic_log_path = "/var/log/panic.log"
    if os.path.exists(panic_log_path):
        viki_code()
        os.remove(panic_log_path)
        print(f"Deleted {panic_log_path}")
    else:
        print(f"{panic_log_path} does not exist. No action needed.")

if __name__ == "__main__":
    check_and_handle_panic_log()

