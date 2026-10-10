#!/usr/bin/env python3
"""Build the ROM download image (same layout as the MRA) from a MAME rom directory.
   mkroms.py <romdir> <outdir>   ->  <outdir>/rom.bin"""
import os, sys

LAYOUT = [  # (file, offset)
    ("136013-104.mn1", 0x0000),   # CPU $4000
    ("136013-103.l1",  0x1000),   # CPU $5000
    ("136013-102.jk1", 0x2000),   # CPU $6000
    ("136013-101.h1",  0x3000),   # CPU $7000
    ("136013-107.r5",  0x4000),   # picture ROM 5R (AREA0)
    ("136013-106.p5",  0x4800),   # picture ROM 5P (AREA1)
    ("136001-213.e7",  0x5000),   # sync PROM 7E
]

src, dst = sys.argv[1], sys.argv[2]
img = bytearray(b"\xff" * 0x5100)
for name, off in LAYOUT:
    data = open(os.path.join(src, name), "rb").read()
    img[off:off + len(data)] = data
os.makedirs(dst, exist_ok=True)
open(os.path.join(dst, "rom.bin"), "wb").write(img)
print(f"rom.bin {len(img)} bytes")
