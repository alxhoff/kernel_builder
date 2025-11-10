#!/usr/bin/env python3
import struct
import sys
import argparse
import serial

# --- Defaults ---
DEFAULT_PORT = '/dev/ttyUSB0'
DEFAULT_BAUD = 115200

# --- Constants ---
CMD_SET_CTRLMODE = 0x03
RAW_PACKET_FORMAT = '<BIBBBB64s' # 73 bytes total

# --- Helper: Verbose Dump (HEX + DECIMAL) ---
def print_data_verbose(label, data):
    print(f"\n--- {label} ({len(data)} bytes) ---")

    # Hex view
    print("[HEX]")
    for i in range(0, len(data), 16):
        chunk = data[i:i+16]
        hex_str = " ".join(f"{b:02X}" for b in chunk)
        print(f"  {i:04X}: {hex_str}")

    # Decimal view
    print("[DECIMAL]")
    for i in range(0, len(data), 16):
        chunk = data[i:i+16]
        # Format decimal with 3 spaces for alignment (0-255)
        dec_str = " ".join(f"{b:3d}" for b in chunk)
        print(f"  {i:04X}: {dec_str}")
    print("-----------------------------------")

# --- COBS Encode Function ---
def cobs_encode(src_bytes):
    dst = bytearray()
    code_ptr = 0
    dst.append(0x01)
    code = 0x01
    for byte in src_bytes:
        if byte == 0:
            dst[code_ptr] = code
            code_ptr = len(dst)
            dst.append(0x01)
            code = 0x01
        else:
            dst.append(byte)
            code += 1
            if code == 0xFF:
                dst[code_ptr] = code
                code_ptr = len(dst)
                dst.append(0x01)
                code = 0x01
    dst[code_ptr] = code
    return dst

def main():
    parser = argparse.ArgumentParser(description="Send SLCANFD configuration packet via serial.")
    parser.add_argument("-p", "--port", default=DEFAULT_PORT, help=f"Serial port (default: {DEFAULT_PORT})")
    parser.add_argument("-b", "--baud", type=int, default=DEFAULT_BAUD, help=f"Baud rate (default: {DEFAULT_BAUD})")
    parser.add_argument("--disable-fd", action="store_true", help="Send disable FD mode command (default is enable)")
    parser.add_argument("-v", "--verbose", action="store_true", help="Show detailed hex/decimal dump of sent packet")

    args = parser.parse_args()

    # --- 1. Prepare Config Data ---
    # Command: SET_CTRLMODE (0x03)
    # Data[0]: 1 = Enable FD, 0 = Disable FD
    fd_mode = 0 if args.disable_fd else 1

    config_data = bytearray(64)
    config_data[0] = fd_mode

    # --- 2. Build 73-byte Raw Packet ---
    # Index = 0 (Config Channel)
    raw_pkt = struct.pack(RAW_PACKET_FORMAT,
                          0,                 # Index 0
                          CMD_SET_CTRLMODE,  # CAN ID holds the command
                          1,                 # Length (1 byte of data used)
                          0, 0, 0,           # Flags, Res0, Res1
                          config_data        # 64-byte data payload
                          )

    # --- 3. COBS Encode & Terminate ---
    cobs_pkt = cobs_encode(raw_pkt)
    final_payload = cobs_pkt + b'\x00'

    if args.verbose:
        print(f"Command: SET_CTRLMODE = {fd_mode}")
        print_data_verbose("RAW PACKET (Expected on STM32)", raw_pkt)
        print_data_verbose("ENCODED PACKET (Wire Data)", final_payload)

    # --- 4. Send via Serial ---
    print(f"\nSending config packet to {args.port} at {args.baud} baud...")
    try:
        with serial.Serial(args.port, args.baud, timeout=1) as ser:
            ser.write(final_payload)
        print("Done.")
    except serial.SerialException as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
