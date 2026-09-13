#!/usr/bin/env python3
import struct

rom = bytearray(512)

# PCI expansion ROM signature
rom[0:2] = b'\x55\xAA'

# Option ROM initialization entry at offset 3:
# RETF -- immediately return from ROM initialization.
rom[3] = 0xCB

# Pointer to PCI Data Structure: offset 0x18
struct.pack_into("<H", rom, 0x18, 0x18)

# PCI Data Structure ("PCIR")
rom[0x18:0x1c] = b"PCIR"

# Vendor ID / Device ID
struct.pack_into("<HH", rom, 0x1c, 0xFFFF, 0xFFFF)

# Vital Product Data pointer
struct.pack_into("<H", rom, 0x20, 0)

# PCI Data Structure length
struct.pack_into("<H", rom, 0x22, 0x18)

# PCI Data Structure revision
rom[0x24] = 0

# Class code: Ethernet controller
rom[0x25:0x28] = b"\x02\x00\x00"

# Image length, in 512-byte units
rom[0x28] = 1

# Revision
struct.pack_into("<H", rom, 0x2a, 0x0100)

# Code type: x86 PC-AT
rom[0x2c] = 0

# Indicator: last image
rom[0x2d] = 0x80

# Checksum: entire ROM must sum to zero modulo 256
rom[0x1f] = (-sum(rom)) & 0xff

with open("dummy.rom", "wb") as f:
    f.write(rom)
