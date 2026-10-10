#!/usr/bin/env python3
"""Decode Big Pink's sixteen BG2 tiles from an original native raster packet."""
import argparse
import hashlib
import json
import struct
from pathlib import Path

from PIL import Image
from verify_raster import ROOT


TILES = [row * 16 + col for row in range(30, 34) for col in range(12, 16)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path)
    args = parser.parse_args()
    cases = json.loads((args.fixture.parent / "cases.json").read_text())
    case = next((entry for entry in cases if entry["name"] == args.fixture.name), None)
    if not case or case["state"] != 8 or case["room"] != 0x9d19:
        raise RuntimeError("Expected original Big Pink gameplay checkpoint")
    vram = (args.fixture / "frame.vram").read_bytes()
    raster = (args.fixture / "frame.raster").read_bytes()
    if len(vram) != 65536 or len(raster) != 262144:
        raise RuntimeError("Invalid raster packet")
    row = raster[100 * 1024:101 * 1024]
    base, tiles, sx, sy = struct.unpack_from("<4H", row, 40)
    if row[0] != 1 or row[109] != 4 or row[65] != 1 or tiles != 0:
        raise RuntimeError("Unexpected BG2 format")
    words = struct.unpack_from("<2048H", vram, base * 2)
    if sorted({word & 1023 for word in words}) != TILES or any((word >> 10) & 7 != 3 for word in words):
        raise RuntimeError("Unexpected original BG2 tile library")
    palette = struct.unpack_from("<256H", row, 256)
    image = Image.new("RGB", (32, 32))
    for number in TILES:
        for y in range(8):
            for x in range(8):
                value = sum(((vram[number * 32 + (plane // 2) * 16 + y * 2 + plane % 2] >> (7 - x)) & 1) << plane for plane in range(4))
                color = palette[48 + value] if value else palette[0]
                image.putpixel(((number % 16 - 12) * 8 + x, (number // 16 - 30) * 8 + y), tuple(((color >> shift) & 31) * 255 // 31 for shift in (0, 5, 10)))
    output = ROOT / "assets/extracted/references/pink_bg2_tiles_original.png"
    image.save(output)
    manifest = {"description": "Original Big Pink BG2 planar tiles, columns 12..15 and rows 30..33, repacked as a 4x4 atlas without changing any cell",
                "room": "9D19", "room_state": "9D26", "frame": case["frame"], "width": 32, "height": 32,
                "tile_size": 8, "tile_columns": 4, "tile_rows": 4, "native_first_column": 12, "native_first_row": 30,
                "used_tiles": TILES, "palette": 3,
                "palette_rgb5": {str(i): [(palette[i] >> shift) & 31 for shift in (0, 5, 10)] for i in range(49, 64)},
                "bg2_map_words": base, "bg2_tiles_words": tiles, "bg2_scroll": [sx, sy],
                "vram_sha256": hashlib.sha256(vram).hexdigest(), "raster_sha256": hashlib.sha256(raster).hexdigest(),
                "png_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
                "rom_sha256": hashlib.sha256((ROOT / "rom_src/Super Metroid (Japan, USA) (En,Ja).sfc").read_bytes()).hexdigest()}
    output.with_suffix(".json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("PINK_BG2_EXTRACT_OK: 16 native BG2 tiles and original CGRAM, unchanged atlas cell arrangement")


if __name__ == "__main__":
    main()
