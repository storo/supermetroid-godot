#!/usr/bin/env python3
"""Decode the 44 Crateria Rocks BG2 cells from a native Parlor checkpoint."""
import argparse
import hashlib
import json
import struct
from pathlib import Path

from PIL import Image
from verify_raster import ROOT

TILES = [row * 16 + col for row in range(12, 16) for col in range(8, 16)] + [row * 16 + col for row in range(30, 32) for col in range(10, 16)]


def atlas_cell(number):
    return (number % 16 - 8, number // 16 - 12) if number < 256 else (number % 16 - 10, number // 16 - 26)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path)
    args = parser.parse_args()
    cases = json.loads((args.fixture.parent / "cases.json").read_text())
    case = next((entry for entry in cases if entry["name"] == args.fixture.name), None)
    if not case or case["state"] != 8 or case["room"] != 0x92fd or case.get("room_state") not in (0x9314, 0x932e):
        raise RuntimeError("Expected original Parlor gameplay")
    vram = (args.fixture / "frame.vram").read_bytes()
    raster = (args.fixture / "frame.raster").read_bytes()
    if len(vram) != 65536 or len(raster) != 262144:
        raise RuntimeError("Invalid native raster packet")
    row = raster[100 * 1024:101 * 1024]
    base, tiles, sx, sy = struct.unpack_from("<4H", row, 40)
    if row[0] != 1 or row[109] != 4 or row[65] != 1 or tiles != 0:
        raise RuntimeError("Unexpected Parlor BG2 format")
    words = struct.unpack_from("<2048H", vram, base * 2)
    if sorted({word & 1023 for word in words}) != TILES or any((word >> 10) & 7 != 4 for word in words):
        raise RuntimeError("Unexpected Crateria Rocks tile library")
    palette = struct.unpack_from("<256H", row, 256)
    image = Image.new("RGB", (64, 48))
    for number in TILES:
        cx, cy = atlas_cell(number)
        for y in range(8):
            for x in range(8):
                value = sum(((vram[number * 32 + (plane // 2) * 16 + y * 2 + plane % 2] >> (7 - x)) & 1) << plane for plane in range(4))
                color = palette[64 + value] if value else palette[0]
                image.putpixel((cx * 8 + x, cy * 8 + y), tuple(((color >> shift) & 31) * 255 // 31 for shift in (0, 5, 10)))
    output = ROOT / "assets/extracted/references/parlor_bg2_tiles_original.png"
    image.save(output)
    manifest = {"description": "Crateria Rocks BG2: native rows 12..15, columns 8..15 in atlas rows 0..3; native rows 30..31, columns 10..15 in atlas rows 4..5, columns 0..5. Four unused cells stay black.",
                "room": "92FD", "room_state": f"{case['room_state']:04X}", "frame": case["frame"], "width": 64, "height": 48,
                "tile_size": 8, "tile_columns": 8, "tile_rows": 6, "used_tiles": TILES, "palette": 4,
                "tile_cells": {str(number): list(atlas_cell(number)) for number in TILES},
                "palette_rgb5": {str(i): [(palette[i] >> shift) & 31 for shift in (0, 5, 10)] for i in range(65, 80)},
                "bg2_map_words": base, "bg2_tiles_words": tiles, "bg2_scroll": [sx, sy],
                "vram_sha256": hashlib.sha256(vram).hexdigest(), "raster_sha256": hashlib.sha256(raster).hexdigest(),
                "png_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
                "rom_sha256": hashlib.sha256((ROOT / "rom_src/Super Metroid (Japan, USA) (En,Ja).sfc").read_bytes()).hexdigest()}
    output.with_suffix(".json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("PARLOR_BG2_EXTRACT_OK: 44 native Crateria Rocks BG2 cells and CGRAM")


if __name__ == "__main__":
    main()
