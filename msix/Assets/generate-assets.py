#!/usr/bin/env python3
"""Generate placeholder Escape Reality logo PNGs (stdlib only, no PIL).

Run:  python3 generate-assets.py
Replace these with real artwork before distributing the package.
"""
import math
import struct
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent

# (filename, width, height)
ASSETS = [
    ("StoreLogo.png", 50, 50),
    ("Square44x44Logo.png", 44, 44),
    ("Square71x71Logo.png", 71, 71),
    ("Square150x150Logo.png", 150, 150),
    ("Square310x310Logo.png", 310, 310),
    ("Wide310x150Logo.png", 310, 150),
]


def chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def write_png(path: Path, width: int, height: int, pixels: bytes) -> None:
    raw = b"".join(
        b"\x00" + pixels[row * width * 3 : (row + 1) * width * 3]
        for row in range(height)
    )
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def pixel(x: int, y: int, width: int, height: int):
    # Dark slate background with a subtle diagonal gradient.
    t = (x + y) / max(width + height, 1)
    r = int(24 + 30 * t)
    g = int(32 + 34 * t)
    b = int(48 + 44 * t)

    # Centered ring (the "reality" circle) with a filled core.
    cx, cy = width / 2, height / 2
    radius = min(width, height) * 0.30
    dist = math.hypot(x - cx, y - cy)
    if abs(dist - radius) < max(2, min(width, height) * 0.03):
        r, g, b = 120, 200, 255
    elif dist < radius * 0.45:
        r, g, b = 120, 200, 255

    # Thin light border.
    border = max(1, min(width, height) // 40)
    if x < border or y < border or x >= width - border or y >= height - border:
        r, g, b = 200, 220, 240

    return r, g, b


def main() -> None:
    for name, width, height in ASSETS:
        pixels = bytearray()
        for y in range(height):
            for x in range(width):
                pixels.extend(pixel(x, y, width, height))
        write_png(HERE / name, width, height, bytes(pixels))
        print(f"wrote {name} ({width}x{height})")


if __name__ == "__main__":
    main()
