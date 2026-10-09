#!/usr/bin/env python3
"""Verify fresh-game return to Crateria, Pit death quota and Zebes awakening in Godot."""
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
    with tempfile.TemporaryDirectory(prefix="sm-awaken-") as directory:
        fixture = Path(directory)
        run([str(ROOT / "native/build/sm_awaken_route"), str(rom), directory], "native_awaken_route.log", "AWAKEN_ROUTE_OK")
        run([args.godot, "--path", str(ROOT), "--script", "tools/native_probe/awaken_test.gd", "--", "--route-fixture", directory],
            "native_awaken_godot.log", "AWAKEN_GODOT_OK")
        route = json.loads((QA / "native_awaken_route.json").read_text())
        required = {"ascent", "return", "combat", "awake"}
        if set(route["captures"]) != required or route["capacity"] != 5 or route["kills"] != 5 or route["quota"] != 5 or not route["zebes_awake"] or route["events"][0] & 1 == 0:
            raise RuntimeError("Incomplete Pit quota/awakening evidence")
        points = fixture / "checkpoints.csv"
        points.write_text("".join(f"{case['frame']},{name}\n" for name, case in sorted(route["captures"].items(), key=lambda pair: pair[1]["frame"])))
        run([str(ROOT / "native/build/sm_raster_oracle"), str(rom), directory, str(fixture / "awaken.inputs"), str(points)],
            "native_awaken_oracle.log", "RASTER_ORACLE_OK")
        comparisons = []
        for name in sorted(required):
            expected = np.frombuffer((fixture / name / "frame.bgra").read_bytes(), np.uint8).reshape(224, 256, 4)[:, :, [2, 1, 0]]
            actual = np.asarray(Image.open(QA / f"native_awaken_{name}_original.png").convert("RGB"))
            if actual.shape != expected.shape:
                raise RuntimeError(f"Unexpected image shape for {name}: {actual.shape}")
            error = np.abs(actual.astype(np.int16) - expected.astype(np.int16))
            Image.fromarray(expected).save(QA / f"native_awaken_{name}_oracle.png")
            comparisons.append({"name": name, "frame": route["captures"][name]["frame"],
                                "pixels": 256 * 224, "mismatched_pixels": int(np.any(error, axis=2).sum()),
                                "max_channel_error": int(error.max())})
        report = {"route": route, "pixel_comparisons": comparisons,
                  "rom_unchanged": before == hashlib.sha256(rom.read_bytes()).hexdigest(),
                  "oracle_used_by_gameplay": False, "whole_campaign_verified": False}
        (QA / "native_awaken_verification.json").write_text(json.dumps(report, indent=2) + "\n")
        if not report["rom_unchanged"] or any(case["mismatched_pixels"] for case in comparisons):
            raise RuntimeError("Awaken raster parity failed; inspect native_awaken_verification.json")
        print(f"AWAKEN_VERIFICATION_OK: {route['frames']} native Godot ticks; return elevator/five original Pit pirates/death quota/Zebes event; {sum(case['pixels'] for case in comparisons)} exact RGB pixels; ROM intact")


if __name__ == "__main__":
    main()
