#!/usr/bin/env python3
"""Replay Ceres through Landing Site in Godot and compare four rendered checkpoints."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile

import numpy as np
from PIL import Image

from verify_raster import ROOT, QA, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot")
    args = parser.parse_args()
    rom = ROOT / "rom_src" / "Super Metroid (Japan, USA) (En,Ja).sfc"
    before = hashlib.sha256(rom.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix="sm-campaign-") as directory:
        fixture = Path(directory)
        run([str(ROOT / "native/build/sm_campaign_route"), str(rom), directory], "native_campaign_route.log", "CAMPAIGN_ROUTE_OK")
        run([args.godot, "--path", str(ROOT), "--script", "tools/native_probe/campaign_test.gd", "--", "--route-fixture", directory],
            "native_campaign_godot.log", "CAMPAIGN_GODOT_OK")
        route = json.loads((QA / "native_campaign_route.json").read_text())
        required = {"ridley", "getaway", "escape", "landing"}
        if set(route["captures"]) != required:
            raise RuntimeError("Missing campaign capture")
        points = fixture / "checkpoints.csv"
        points.write_text("".join(f"{case['frame']},{name}\n" for name, case in sorted(route["captures"].items(), key=lambda pair: pair[1]["frame"])))
        run([str(ROOT / "native/build/sm_raster_oracle"), str(rom), directory, str(fixture / "route.inputs"), str(points)],
            "native_campaign_oracle.log", "RASTER_ORACLE_OK")
        comparison = []
        for name in sorted(required):
            expected = np.frombuffer((fixture / name / "frame.bgra").read_bytes(), np.uint8).reshape(224, 256, 4)[:, :, [2, 1, 0]]
            actual = np.asarray(Image.open(QA / f"native_campaign_{name}_original.png").convert("RGB"))
            if actual.shape != expected.shape:
                raise RuntimeError(f"Unexpected image shape for {name}: {actual.shape}")
            error = np.abs(actual.astype(np.int16) - expected.astype(np.int16))
            mismatches = int(np.any(error, axis=2).sum())
            Image.fromarray(expected).save(QA / f"native_campaign_{name}_oracle.png")
            comparison.append({"name": name, "frame": route["captures"][name]["frame"],
                               "pixels": 256 * 224, "mismatched_pixels": mismatches,
                               "max_channel_error": int(error.max())})
        report = {"route": route, "pixel_comparisons": comparison,
                  "rom_unchanged": before == hashlib.sha256(rom.read_bytes()).hexdigest(),
                  "oracle_used_by_gameplay": False, "whole_campaign_verified": False}
        (QA / "native_campaign_verification.json").write_text(json.dumps(report, indent=2) + "\n")
        if not report["rom_unchanged"] or any(case["mismatched_pixels"] for case in comparison):
            raise RuntimeError("Campaign raster parity failed; inspect native_campaign_verification.json")
        print(f"CAMPAIGN_VERIFICATION_OK: {route['frames']} native Godot ticks; Ceres/Ridley/escape/playable Landing Site; 229376 exact RGB pixels; ROM intact")


if __name__ == "__main__":
    main()
