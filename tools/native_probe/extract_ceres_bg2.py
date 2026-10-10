#!/usr/bin/env python3
"""Decode the original Ceres BG2 tilemap from a native drawing packet."""
import argparse
import hashlib
import json
import struct
from pathlib import Path

from PIL import Image
from verify_raster import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path, help="ceres_corridor fixture from sm_raster_oracle")
    args = parser.parse_args()
    cases = json.loads((args.fixture.parent / "cases.json").read_text())
    case = next((item for item in cases if item["name"] == args.fixture.name), None)
    if not case or case["state"] != 8 or case["room"] != 0xdf8d:
        raise RuntimeError("Expected a native Ceres corridor gameplay fixture")
    vram = (args.fixture / "frame.vram").read_bytes()
    raster = (args.fixture / "frame.raster").read_bytes()
    if len(vram) != 65536 or len(raster) != 262144:
        raise RuntimeError("Invalid native drawing packet size")
    row = raster[100 * 1024:101 * 1024]
    base, tiles, sx, sy = struct.unpack_from("<4H", row, 40)
    flags, depth = row[65], row[109]
    if row[0] != 1 or depth != 4 or flags != 1:
        raise RuntimeError("Expected Ceres 4bpp wide BG2 tilemap")
    palette = struct.unpack_from("<256H", row, 256)
    image = Image.new("RGB", (512, 256))
    pixels = image.load()
    used = set()
    for y in range(256):
        for x in range(512):
            tx, ty = x // 8, y // 8
            address = (base + ty * 32 + (tx & 31) + (1024 if tx & 32 else 0)) & 32767
            word = struct.unpack_from("<H", vram, address * 2)[0]
            px, py = x & 7, y & 7
            if word & 0x4000:
                px = 7 - px
            if word & 0x8000:
                py = 7 - py
            tile_address = tiles * 2 + (word & 1023) * 32
            value = 0
            for plane in range(4):
                byte = vram[(tile_address + (plane // 2) * 16 + py * 2 + plane % 2) & 65535]
                value |= ((byte >> (7 - px)) & 1) << plane
            index = value + ((word >> 10) & 7) * 16 if value else 0
            used.add(index)
            color = palette[index]
            components = [(color >> shift) & 31 for shift in (0, 5, 10)]
            pixels[x, y] = tuple((c << 3) | (c >> 2) for c in components)
    destination = ROOT / "assets/extracted/references/ceres_bg2_original.png"
    image.save(destination)
    manifest = {"description": "Original Ceres BG2, decoded from VRAM planar tiles, tilemap and CGRAM; no PPU framebuffer used",
                "room": "DF8D", "frame": case["frame"], "width": 512, "height": 256,
                "bg2_map_words": base, "bg2_tiles_words": tiles, "bg2_scroll": [sx, sy],
                "flags": flags, "depth": depth, "palette_indices": sorted(used),
                "palette_rgb5": {str(index): [(palette[index] >> shift) & 31 for shift in (0,5,10)] for index in sorted(used)},
                "vram_sha256": hashlib.sha256(vram).hexdigest(), "raster_sha256": hashlib.sha256(raster).hexdigest(),
                "png_sha256": hashlib.sha256(destination.read_bytes()).hexdigest(),
                "rom_sha256": hashlib.sha256((ROOT / "rom_src/Super Metroid (Japan, USA) (En,Ja).sfc").read_bytes()).hexdigest()}
    destination.with_suffix(".json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("CERES_BG2_EXTRACT_OK: 512x256 original background, native VRAM/CGRAM/tilemap")


if __name__ == "__main__":
    main()
