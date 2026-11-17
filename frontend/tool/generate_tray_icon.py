#!/usr/bin/env python3
"""Regenerate `assets/icon/tray.ico` from `assets/icon/icon.png`.

Why a hand-rolled ICO instead of `Pillow.save(format="ICO")`: Windows loads
the tray icon through `LoadImage(IMAGE_ICON)`, which rejects 256×256
PNG-compressed entries (the default Pillow output) — the tray then fails with
"Unable to load tray icon". This script writes uncompressed 32bpp DIB entries
with an AND mask for 16/20/24/32/48/64 px so Windows always finds a small
image.

Usage (needs Pillow):  python tool/generate_tray_icon.py
"""

from __future__ import annotations

import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets/icon/icon.png"
TARGET = ROOT / "assets/icon/tray.ico"
SIZES = (16, 20, 24, 32, 48, 64)


def encode_entry(image: Image.Image, size: int) -> bytes:
    scaled = image.resize((size, size), Image.LANCZOS)
    pixels = scaled.load()
    # XOR 位图：BGRA，自下而上。
    xor = bytearray()
    for y in range(size - 1, -1, -1):
        for x in range(size):
            r, g, b, a = pixels[x, y]
            xor += bytes((b, g, r, a))
    # AND 掩码：32bpp 已有 alpha，掩码全 0；每行按 4 字节对齐。
    stride = ((size + 31) // 32) * 4
    mask = bytes(stride * size)
    header = struct.pack(
        "<IiiHHIIiiII", 40, size, size * 2, 1, 32, 0, len(xor), 0, 0, 0, 0
    )
    return header + bytes(xor) + mask


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    entries = [(size, encode_entry(source, size)) for size in SIZES]

    out = bytearray(struct.pack("<HHH", 0, 1, len(entries)))
    offset = 6 + 16 * len(entries)
    for size, data in entries:
        out += struct.pack(
            "<BBBBHHII", size, size, 0, 0, 1, 32, len(data), offset
        )
        offset += len(data)
    for _, data in entries:
        out += data

    TARGET.write_bytes(out)
    print(f"wrote {TARGET.relative_to(ROOT)} ({len(out)} bytes, {len(entries)} sizes)")


if __name__ == "__main__":
    main()
