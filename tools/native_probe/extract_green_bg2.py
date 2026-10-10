#!/usr/bin/env python3
"""Extract Green Brinstar BG2 tile artwork from native VRAM and CGRAM."""
import argparse
import hashlib
import json
import struct
from pathlib import Path

from PIL import Image
from verify_raster import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path, help="Green Brinstar main-shaft native raster checkpoint")
    args = parser.parse_args()
    cases = json.loads((args.fixture.parent / "cases.json").read_text())
    case = next((item for item in cases if item["name"] == args.fixture.name), None)
    if not case or case["state"] != 8 or case["room"] != 0x9ad9:
        raise RuntimeError("Expected Green Brinstar main-shaft gameplay")
    vram = (args.fixture / "frame.vram").read_bytes()
    raster = (args.fixture / "frame.raster").read_bytes()
    if len(vram) != 65536 or len(raster) != 262144:
        raise RuntimeError("Invalid native drawing packet")
    row = raster[100 * 1024:101 * 1024]
    base, tiles, sx, sy = struct.unpack_from("<4H", row, 40)
    if row[0] != 1 or row[109] != 4 or row[65] != 1 or tiles != 0:
        raise RuntimeError("Unexpected Green Brinstar BG2 format")
    palette = struct.unpack_from("<256H", row, 256)
    words = struct.unpack_from("<2048H", vram, base * 2)
    used = sorted({word & 1023 for word in words if (word >> 10) & 7 == 7 and 224 <= (word & 1023) < 352})
    # Preserve native 16-column 8x8-tile coordinates, rows 14..21. The renderer
    # samples these same tile numbers/flips from the live streamed BG2 map.
    image = Image.new("RGB", (128, 64))
    pixels = image.load()
    for number in used:
        for y in range(8):
            for x in range(8):
                value = sum(((vram[number * 32 + (plane // 2) * 16 + y * 2 + plane % 2] >> (7 - x)) & 1) << plane for plane in range(4))
                color = palette[112 + value] if value else palette[0]
                pixels[(number % 16) * 8 + x, (number // 16 - 14) * 8 + y] = tuple(((color >> shift) & 31) * 255 // 31 for shift in (0, 5, 10))
    destination = ROOT / "assets/extracted/references/green_bg2_tiles_original.png"
    image.save(destination)
    manifest = {"description": "Green Brinstar BG2 tile atlas, decoded from native planar VRAM/CGRAM; native tile coordinates retained, unused cells black",
                "room": "9AD9", "room_state": "9AE6", "frame": case["frame"], "width": 128, "height": 64,
                "first_tile": 224, "tile_columns": 16, "tile_rows": 8, "tile_size": 8, "used_tiles": used,
                "palette": 7, "palette_rgb5": {str(index): [(palette[index] >> shift) & 31 for shift in (0, 5, 10)] for index in range(113, 128)},
                "bg2_map_words": base, "bg2_tiles_words": tiles, "bg2_scroll": [sx, sy],
                "vram_sha256": hashlib.sha256(vram).hexdigest(), "raster_sha256": hashlib.sha256(raster).hexdigest(),
                "png_sha256": hashlib.sha256(destination.read_bytes()).hexdigest(),
                "rom_sha256": hashlib.sha256((ROOT / "rom_src/Super Metroid (Japan, USA) (En,Ja).sfc").read_bytes()).hexdigest()}
    destination.with_suffix(".json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"GREEN_BG2_EXTRACT_OK: {len(used)} original 8x8 tiles, native atlas coordinates/VRAM/CGRAM")


if __name__ == "__main__":
    main()
