#!/usr/bin/env python3
import struct
import sys
import serial # Requires: sudo pacman -S python-pyserial

# --- Configuration ---
SERIAL_PORT = '/dev/ttyUSB0'
BAUD_RATE = 115200

# Target CAN Interface Index (1 = can0, 2 = can1)
DEV_INDEX = 1

# CAN Frame Details
CAN_ID = 0x123
CAN_PAYLOAD = b'\xDE\xAD\xBE\xEF'

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

# --- 1. Build the 73-byte Raw Packet ---
RAW_PACKET_FORMAT = '<BIBBBB64s'

# Prepare data: must be exactly 64 bytes, padded with nulls
data_padded = CAN_PAYLOAD + (b'\x00' * (64 - len(CAN_PAYLOAD)))

raw_pkt = struct.pack(RAW_PACKET_FORMAT,
                      DEV_INDEX,         # Index (1 byte)
                      CAN_ID,            # CAN ID (4 bytes)
                      len(CAN_PAYLOAD),  # Length (1 byte)
                      0,                 # Flags (1 byte)
                      0,                 # Res0 (1 byte)
                      0,                 # Res1 (1 byte)
                      data_padded        # Data (64 bytes)
                      )

print_data_verbose("RAW PACKET (Expected after decoding on STM32)", raw_pkt)

# --- 2. COBS Encode ---
cobs_pkt = cobs_encode(raw_pkt)

# --- 3. Add Terminator ---
final_payload = cobs_pkt + b'\x00'

print_data_verbose("ENCODED PACKET (What is sent over wire)", final_payload)

# --- 4. Send directly to Serial Port ---
print(f"\nSending {len(final_payload)} bytes to {SERIAL_PORT} at {BAUD_RATE} baud...")

try:
    # Open port, send data, close port automatically
    with serial.Serial(SERIAL_PORT, BAUD_RATE) as ser:
        ser.write(final_payload)
    print("Done.")
except serial.SerialException as e:
    print(f"\nError opening serial port: {e}")
    print("Hints: Check if the device exists, if your user is in the 'dialout'/'uucp' group, or if another program (minicom) is using it.")
    sys.exit(1)
