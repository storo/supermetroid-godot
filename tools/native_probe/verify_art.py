#!/usr/bin/env python3
"""Verify Landing Site remastered BG2, protected layers and original RGB parity."""
import argparse
import hashlib
import json
import shutil
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

from verify_raster import ROOT, QA, run


def rgb(name):
    return np.asarray(Image.open(QA / f"native_art_{name}.png").convert("RGB"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot")
    args = parser.parse_args()
    rom = ROOT / "rom_src/Super Metroid (Japan, USA) (En,Ja).sfc"
    before = hashlib.sha256(rom.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix="sm-native-art-") as directory:
        fixture = Path(directory)
        run([str(ROOT / "native/build/sm_campaign_route"), str(rom), directory], "native_art_route.log", "CAMPAIGN_ROUTE_OK")
        run([args.godot, "--path", str(ROOT), "--script", "tools/native_probe/art_test.gd", "--", "--route-fixture", directory],
            "native_art_godot.log", "ART_GODOT_OK")
        route = json.loads((QA / "native_art_route.json").read_text())
        if not route["state_trace_matches"] or not route["presentation_leaves_core_unchanged"] or route["room"] != 0x91F8:
            raise RuntimeError("Missing native gameplay/presentation evidence")
        points = fixture / "points.csv"
        points.write_text(f"{route['frames']},landing\n")
        run([str(ROOT / "native/build/sm_raster_oracle"), str(rom), directory, str(fixture / "route.inputs"), str(points)],
            "native_art_oracle.log", "RASTER_ORACLE_OK")
        expected = np.frombuffer((fixture / "landing/frame.bgra").read_bytes(), np.uint8).reshape(224, 256, 4)[:, :, [2, 1, 0]]
        original, restored = rgb("original"), rgb("original_restored")
        filtered, remastered, parallax = rgb("filtered"), rgb("remastered"), rgb("parallax")
        layers = np.asarray(Image.open(QA / "native_art_layers.png").convert("RGBA"))
        if original.shape != expected.shape or filtered.shape != (448, 512, 3) or layers.shape != (224, 256, 4):
            raise RuntimeError("Unexpected capture dimensions")
        eligible = (layers[:, :, 1] == 1) & (layers[:, :, 3] != 0)
        eligible[:32] = False
        eligible = np.repeat(np.repeat(eligible, 2, axis=0), 2, axis=1)
        changed = np.any(remastered != filtered, axis=2)
        moved = np.any(parallax != remastered, axis=2)
        checks = {
            "original_mismatched_pixels": int(np.any(original != expected, axis=2).sum()),
            "restored_original_mismatched_pixels": int(np.any(restored != expected, axis=2).sum()),
            "protected_pixels": int((~eligible).sum()),
            "protected_mismatched_pixels": int((changed & ~eligible).sum()),
            "background_changed_pixels": int((changed & eligible).sum()),
            "parallax_changed_pixels": int((moved & eligible).sum()),
            "parallax_protected_mismatched_pixels": int((moved & ~eligible).sum()),
            "map_excluded_mismatched_pixels": int(np.any(rgb("map_excluded") != filtered, axis=2).sum()),
            "room_excluded_mismatched_pixels": int(np.any(rgb("room_excluded") != filtered, axis=2).sum()),
            "fade_zero_mismatched_pixels": int(np.any(rgb("fade_zero") != 0, axis=2).sum()),
            "forced_blank_mismatched_pixels": int(np.any(rgb("forced_blank") != 0, axis=2).sum()),
        }
        report = {"route": route, "checks": checks, "rom_unchanged": before == hashlib.sha256(rom.read_bytes()).hexdigest(),
                  "oracle_used_by_gameplay": False, "whole_campaign_verified": False, "full_asset_redraw_complete": False}
        (QA / "native_art_verification.json").write_text(json.dumps(report, indent=2) + "\n")
        failures = [name for name, value in checks.items() if "mismatched" in name and value]
        if failures or checks["background_changed_pixels"] < 10000 or checks["parallax_changed_pixels"] < 1000 or checks["protected_pixels"] < 10000 or not report["rom_unchanged"]:
            raise RuntimeError(f"Native art verification failed: {failures}; inspect native_art_verification.json")
        print(f"ART_VERIFICATION_OK: {route['frames']} native ticks; original/restored exact RGB; {checks['protected_pixels']} protected HUD/terrain/sprite pixels unchanged; {checks['background_changed_pixels']} background pixels replaced; parallax and map/room exclusion; ROM intact")


if __name__ == "__main__":
    main()
