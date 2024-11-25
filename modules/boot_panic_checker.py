#!/usr/bin/env python3

import os
import viki

VIKI = viki.get_logger(__name__)
panic_log_path = "/var/log/panic.log"

def viki_code():
    try:
        with open(panic_log_path) as f:
            log = f.read()
            VIKI.error("KERNEL_PANIC_LOGGER_PANIC_DETECTED", log)
    except Exception as e:
        print(f"Failed to open log: {}", e)

def check_and_handle_panic_log():
    if os.path.exists(panic_log_path):
        viki_code()
        os.remove(panic_log_path)
        print(f"Deleted {panic_log_path}")
    else:
        print(f"{panic_log_path} does not exist. No action needed.")

if __name__ == "__main__":
    check_and_handle_panic_log()

