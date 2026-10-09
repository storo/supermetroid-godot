#!/usr/bin/env python3
"""Verify fresh-game first missiles, message rendering and weapon use in Godot."""
import argparse
import hashlib
import json
import shutil
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

from verify_raster import ROOT, QA, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot")
    args = parser.parse_args()
    rom = ROOT / "rom_src/Super Metroid (Japan, USA) (En,Ja).sfc"
    before = hashlib.sha256(rom.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix="sm-missile-") as directory:
        fixture = Path(directory)
        run([str(ROOT / "native/build/sm_missile_route"), str(rom), directory], "native_missile_route.log", "MISSILE_ROUTE_OK")
        run([args.godot, "--path", str(ROOT), "--script", "tools/native_probe/missile_test.gd", "--", "--route-fixture", directory],
            "native_missile_godot.log", "MISSILE_GODOT_OK")
        route = json.loads((QA / "native_missile_route.json").read_text())
        required = {"construction", "pickup", "fired", "control"}
        if set(route["captures"]) != required or route["capacity"] != 5 or route["missiles"] != 4 or not route["missile_fired"]:
            raise RuntimeError("Incomplete missile acquisition/use evidence")
        points = fixture / "checkpoints.csv"
        points.write_text("".join(f"{case['frame']},{name}\n" for name, case in sorted(route["captures"].items(), key=lambda pair: pair[1]["frame"])))
        run([str(ROOT / "native/build/sm_raster_oracle"), str(rom), directory, str(fixture / "missile.inputs"), str(points)],
            "native_missile_oracle.log", "RASTER_ORACLE_OK")
        comparisons = []
        for name in sorted(required):
            expected = np.frombuffer((fixture / name / "frame.bgra").read_bytes(), np.uint8).reshape(224, 256, 4)[:, :, [2, 1, 0]]
            actual = np.asarray(Image.open(QA / f"native_missile_{name}_original.png").convert("RGB"))
            if actual.shape != expected.shape:
                raise RuntimeError(f"Unexpected image shape for {name}: {actual.shape}")
            error = np.abs(actual.astype(np.int16) - expected.astype(np.int16))
            Image.fromarray(expected).save(QA / f"native_missile_{name}_oracle.png")
            comparisons.append({"name": name, "frame": route["captures"][name]["frame"],
                                "pixels": 256 * 224, "mismatched_pixels": int(np.any(error, axis=2).sum()),
                                "max_channel_error": int(error.max())})
        report = {"route": route, "pixel_comparisons": comparisons,
                  "rom_unchanged": before == hashlib.sha256(rom.read_bytes()).hexdigest(),
                  "oracle_used_by_gameplay": False, "whole_campaign_verified": False}
        (QA / "native_missile_verification.json").write_text(json.dumps(report, indent=2) + "\n")
        if not report["rom_unchanged"] or any(case["mismatched_pixels"] for case in comparisons):
            raise RuntimeError("Missile raster parity failed; inspect native_missile_verification.json")
        print(f"MISSILE_VERIFICATION_OK: {route['frames']} native Godot ticks; first missile PLM/message/selection/projectile/ammo/cancel/control; {sum(case['pixels'] for case in comparisons)} exact RGB pixels; ROM intact")


if __name__ == "__main__":
    main()
