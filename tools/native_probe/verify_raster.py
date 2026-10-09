#!/usr/bin/env python3
"""Compare Godot's native tile renderer with an offline PPU oracle, not gameplay."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
QA = ROOT / "docs" / "qa"


def run(command, name, marker):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=180)
    output = result.stdout + result.stderr
    (QA / name).write_text(output)
    if result.returncode or marker not in output or "SCRIPT ERROR:" in output or "ERROR:" in output:
        raise RuntimeError(f"{name}: failed (exit {result.returncode}); inspect its log")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot")
    parser.add_argument("--rom", type=Path, default=ROOT / "rom_src" / "Super Metroid (Japan, USA) (En,Ja).sfc")
    parser.add_argument("--oracle", type=Path, default=ROOT / "native" / "build" / "sm_raster_oracle")
    args = parser.parse_args()
    before = hashlib.sha256(args.rom.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix="sm-raster-") as directory:
        run([str(args.oracle), str(args.rom), directory], "native_raster_oracle.log", "RASTER_ORACLE_OK")
        cases = json.loads((Path(directory) / "cases.json").read_text())
        required_cases = {"intro_1200", "intro_2400", "intro_4800", "intro_7200", "ceres_elevator", "ceres_corridor"}
        if {case["name"] for case in cases} != required_cases:
            raise RuntimeError("The oracle did not produce the complete expected capture set")
        for case in cases:
            fixture = Path(directory) / case["name"]
            run([args.godot, "--path", str(ROOT), "--script", "tools/native_probe/raster_test.gd", "--", "--raster-fixture", str(fixture)],
                f"native_raster_{case['name']}.log", "RASTER_GODOT_OK")
            expected = np.frombuffer((fixture / "frame.bgra").read_bytes(), np.uint8).reshape(224, 256, 4)[:, :, [2, 1, 0]]
            actual = np.asarray(Image.open(fixture / "godot.png").convert("RGB"))
            if actual.shape != expected.shape:
                raise RuntimeError(f"Unexpected Godot image dimensions: {actual.shape}")
            difference = np.abs(actual.astype(np.int16) - expected.astype(np.int16))
            raster = np.frombuffer((fixture / "frame.raster").read_bytes(), np.uint8).reshape(256, 1024)
            case.update({
                "pixels": 256 * 224,
                "mismatched_pixels": int(np.any(difference, axis=2).sum()),
                "max_channel_error": int(difference.max()),
                "scanline_modes": sorted(map(int, np.unique(raster[:224, 0]))),
                "mode_changes_at_rows": [i for i in range(1, 224) if raster[i, 0] != raster[i - 1, 0]],
                "nonblack_pixels": int(np.any(expected != 0, axis=2).sum()),
            })
            Image.fromarray(expected).save(QA / f"native_raster_{case['name']}_oracle.png")
            Image.fromarray(actual).save(QA / f"native_raster_{case['name']}_godot.png")
            if case["name"] == "ceres_elevator":
                Image.fromarray(expected).save(QA / "native_ceres_oracle.png")
                Image.fromarray(actual).save(QA / "native_ceres_raster_original.png")
            if case["nonblack_pixels"] == 0:
                raise RuntimeError(f"Unexpected blank capture: {case['name']}")
        after = hashlib.sha256(args.rom.read_bytes()).hexdigest()
        report = {
            "cases": cases,
            "pixels": sum(case["pixels"] for case in cases),
            "mismatched_pixels": sum(case["mismatched_pixels"] for case in cases),
            "rom_unchanged": before == after,
            "oracle_used_by_gameplay": False, "whole_campaign_verified": False,
        }
        (QA / "native_raster_comparison.json").write_text(json.dumps(report, indent=2) + "\n")
        if report["mismatched_pixels"] or before != after:
            raise RuntimeError(f"Raster mismatch: {report['mismatched_pixels']} pixels; ROM unchanged: {before == after}")
        print(f"RASTER_PARITY_OK: {len(cases)} captures, {report['pixels']} exact RGB pixels; ROM intact")


if __name__ == "__main__":
    main()
