#!/usr/bin/env python3

import os
import viki

VIKI = viki.get_logger(__name__)
LOG_FILE_PATH = "/var/log/panic.log"
PSTORE_PATH = "/sys/fs/pstore"
PANIC_FLAG = "CARTKEN_KERNEL_HAS_PANICKED"

def CheckPanicAndCompileLog():
    if not os.path.exists(PSTORE_PATH):
        print(f"Error: {PSTORE_PATH} does not exist.")
        return False

    all_contents = ""
    flag_found = False

    for root, _, files in os.walk(PSTORE_PATH):
        for file_name in files:
            file_path = os.path.join(root, file_name)
            try:
                with open(file_path, 'r') as file:
                    contents = file.read()
                    all_contents += f"\n--- Contents of {file_name} ---\n"
                    all_contents += contents
                    if PANIC_FLAG in contents:
                        flag_found = True
            except Exception as e:
                print(f"[panic checker] Failed to read {file_path}: {e}")

    if flag_found:
        try:
            with open(LOG_FILE_PATH, 'w') as log_file:
                log_file.write(all_contents)
        except Exception as e:
            print(f"[panic checker] Failed to write to {LOG_FILE_PATH}: {e}")

    return flag_found

def LogViki():
    try:
        with open(LOG_FILE_PATH) as f:
            log = f.read()
            VIKI.error("KERNEL_PANIC_LOGGER_PANIC_DETECTED", log)
    except Exception as e:
        print(f"[panic checker] Failed to open log: {e}")

def CheckPanicLogs():
    if CheckPanicAndCompileLog():
        LogViki()
        os.remove(LOG_FILE_PATH)
        print(f"[panic checker] Deleted {LOG_FILE_PATH}")
    else:
        print(f"[panic checker] {LOG_FILE_PATH} does not exist. No action needed.")

if __name__ == "__main__":
    CheckPanicLogs()

