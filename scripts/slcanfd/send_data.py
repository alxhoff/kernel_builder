#!/usr/bin/env python3
import struct
import sys
import argparse
import serial
import can # Requires: sudo pacman -S python-can

# --- Constants ---
DEFAULT_SERIAL_PORT = '/dev/ttyUSB0'
DEFAULT_BAUD = 115200
DEFAULT_CAN_ID = "0x123"
DEFAULT_CAN_DATA = "DEADBEEF"
DEFAULT_DEV_INDEX = 1

# --- Helper: Verbose Dump (HEX + DECIMAL) ---
def print_data_verbose(label, data):
    print(f"\n--- {label} ({len(data)} bytes) ---")
    print("[HEX]")
    for i in range(0, len(data), 16):
        chunk = data[i:i+16]
        hex_str = " ".join(f"{b:02X}" for b in chunk)
        print(f"  {i:04X}: {hex_str}")
    print("[DECIMAL]")
    for i in range(0, len(data), 16):
        chunk = data[i:i+16]
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

# --- Path 1: Send via Serial (Gateway Test) ---
def send_serial_cobs(args, can_id, payload):
    print(f"Sending via SERIAL ({args.serial}) at {args.baud} baud...")
    print(f"  Index: {args.index}, ID: 0x{can_id:X}, Data: {payload.hex().upper()}")

    # 1. Build the 73-byte Raw Packet
    RAW_PACKET_FORMAT = '<BIBBBB64s'
    data_padded = payload + (b'\x00' * (64 - len(payload)))
    raw_pkt = struct.pack(RAW_PACKET_FORMAT,
                          args.index,      # Index
                          can_id,          # CAN ID
                          len(payload),    # Length
                          0, 0, 0,         # Flags, Res0, Res1
                          data_padded      # Data
                          )

    # 2. COBS Encode
    cobs_pkt = cobs_encode(raw_pkt)
    final_payload = cobs_pkt + b'\x00'

    if args.verbose:
        print_data_verbose("RAW PACKET (to be decoded by STM32)", raw_pkt)
        print_data_verbose("ENCODED PACKET (sent over wire)", final_payload)

    # 3. Send
    print(f"Sending {len(final_payload)} bytes...")
    try:
        with serial.Serial(args.serial, args.baud, timeout=1) as ser:
            ser.write(final_payload)
        print(f"Successfully sent {len(final_payload)} bytes to {args.serial}.")
    except serial.SerialException as e:
        print(f"Error: {e}")
        sys.exit(1)

# --- Path 2: Send via Native CAN (Driver Test) ---
def send_native_can(args, can_id, payload):
    print(f"Sending via NATIVE CAN interface ({args.can})...")

    is_extended = can_id > 0x7FF

    try:
        # Create the message
        msg = can.Message(
            arbitration_id=can_id,
            data=payload,
            is_extended_id=is_extended
        )

        # More explicit output
        print(f"  ID: 0x{can_id:X}, Data: {payload.hex().upper()}")
        if args.verbose:
            print(f"  Verbose: {msg}")

        # Open the SocketCAN bus, send, and shut down
        # FIX: Replaced 'bustype' with 'interface' to remove DeprecationWarning
        with can.interface.Bus(channel=args.can, interface='socketcan') as bus:
            bus.send(msg)

        print("Successfully sent packet on bus.")
    except Exception as e:
        print(f"Error sending CAN message: {e}")
        print("Hint: Is the 'python-can' library installed? Is the interface (e.g., 'can0') up?")
        sys.exit(1)

# --- Main ---
def main():
    parser = argparse.ArgumentParser(description="Send a CAN packet via SLCANFD (Serial) or Native SocketCAN.")

    # Mode selection
    group = parser.add_mutually_exclusive_group()
    group.add_argument("-c", "--can", help="Send natively via a CAN interface (e.g., 'can0'). Bypasses serial.")
    group.add_argument("-s", "--serial", default=DEFAULT_SERIAL_PORT, help=f"Send via serial port (default: {DEFAULT_SERIAL_PORT})")

    # Packet content
    parser.add_argument("--id", default=DEFAULT_CAN_ID, help=f"CAN ID in hex (default: {DEFAULT_CAN_ID})")
    parser.add_argument("--data", default=DEFAULT_CAN_DATA, help=f"CAN payload in hex (default: {DEFAULT_CAN_DATA})")

    # Serial-only options
    parser.add_argument("--index", type=int, default=DEFAULT_DEV_INDEX, help=f"Device index (for serial mode only, default: {DEFAULT_DEV_INDEX})")
    parser.add_argument("-b", "--baud", type=int, default=DEFAULT_BAUD, help=f"Baud rate (for serial mode only, default: {DEFAULT_BAUD})")

    # General
    parser.add_argument("-v", "--verbose", action="store_true", help="Show detailed hex/decimal dump of sent packet")

    args = parser.parse_args()

    # --- Prepare payload ---
    try:
        can_id = int(args.id, 16)
    except ValueError:
        print(f"Error: Invalid CAN ID '{args.id}'. Must be hex (e.g., '0x123' or '123').")
        sys.exit(1)

    try:
        payload = bytes.fromhex(args.data)
        if len(payload) > 64:
             print(f"Error: CAN data '{args.data}' is too long ({len(payload)} bytes). Max 64.")
             sys.exit(1)
    except ValueError:
        print(f"Error: Invalid CAN data '{args.data}'. Must be hex string (e.g., 'DEADBEEF').")
        sys.exit(1)

    # --- Route to the correct send function ---
    if args.can:
        send_native_can(args, can_id, payload)
    else:
        send_serial_cobs(args, can_id, payload)

if __name__ == '__main__':
    main()
