#!/usr/bin/env python3
"""Verify the fresh-game native route through bombs and Bomb Torizo in Godot."""
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

from verify_raster import ROOT, QA, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot")
    parser.add_argument("--input-prefix", type=Path, default=ROOT / "tools/native_probe/fixtures/bomb_prefix.inputs", help="Recorded controller prefix; replayed from a fresh game, never a save state")
    parser.add_argument("--plan-from-start", action="store_true", help="Regenerate the initial route with the POSIX controller instead of replaying the recorded prefix")
    args = parser.parse_args()
    rom = ROOT / "rom_src/Super Metroid (Japan, USA) (En,Ja).sfc"
    before = hashlib.sha256(rom.read_bytes()).hexdigest()
    prefix = None if args.plan_from_start else args.input_prefix
    default_prefix = ROOT / "tools/native_probe/fixtures/bomb_prefix.inputs"
    if prefix and prefix.resolve() == default_prefix.resolve():
        manifest = json.loads(default_prefix.with_suffix(".json").read_text())
        data = prefix.read_bytes()
        if hashlib.sha256(data).hexdigest() != manifest["sha256"] or len(data) != manifest["frames"] * 2 or before != manifest["rom_sha256"]:
            raise RuntimeError("Recorded input prefix or ROM does not match its manifest")
    with tempfile.TemporaryDirectory(prefix="sm-bomb-verify-") as directory:
        fixture = Path(directory)
        command = [str(ROOT / "native/build/sm_bomb_route"), str(rom), directory]
        if prefix:
            command.append(str(prefix.resolve()))
        # Planning uses isolated POSIX children; the complete parent input/state
        # trace is the evidence replayed below, including any supplied prefix.
        with (QA / "native_bomb_controller.log").open("w") as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=1800)
        if result.returncode or "BOMB_ROUTE_OK" not in (QA / "native_bomb_controller.log").read_text():
            raise RuntimeError("Incomplete bomb controller route; inspect native_bomb_controller.log")
        run([args.godot, "--path", str(ROOT), "--script", "tools/native_probe/bomb_test.gd", "--", "--route-fixture", directory],
            "native_bomb_godot.log", "BOMB_GODOT_OK", timeout=600)
        route = json.loads((QA / "native_bomb_route.json").read_text())
        required = {"climb", "passage", "red_door", "pickup", "combat", "bomb", "defeated"}
        if (set(route["captures"]) != required or route["flyway_missiles_fired"] != 5
                or route["boss_initial_health"] != 800 or not route["bomb_placed"]
                or not route["bomb_torizo_defeated"] or route["bosses"][0] & 4 == 0):
            raise RuntimeError("Incomplete native bomb/boss evidence")
        points = fixture / "checkpoints.csv"
        points.write_text("".join(f"{case['frame']},{name}\n" for name, case in sorted(route["captures"].items(), key=lambda pair: pair[1]["frame"])))
        run([str(ROOT / "native/build/sm_raster_oracle"), str(rom), directory, str(fixture / "bomb.inputs"), str(points)],
            "native_bomb_oracle.log", "RASTER_ORACLE_OK", timeout=600)
        comparisons = []
        for name in sorted(required):
            expected = np.frombuffer((fixture / name / "frame.bgra").read_bytes(), np.uint8).reshape(224, 256, 4)[:, :, [2, 1, 0]]
            actual = np.asarray(Image.open(QA / f"native_bomb_{name}_original.png").convert("RGB"))
            if actual.shape != expected.shape:
                raise RuntimeError(f"Unexpected image shape for {name}: {actual.shape}")
            error = np.abs(actual.astype(np.int16) - expected.astype(np.int16))
            Image.fromarray(expected).save(QA / f"native_bomb_{name}_oracle.png")
            comparisons.append({"name": name, "frame": route["captures"][name]["frame"],
                                "pixels": 256 * 224, "mismatched_pixels": int(np.any(error, axis=2).sum()),
                                "max_channel_error": int(error.max())})
        report = {"route": route, "pixel_comparisons": comparisons,
                  "prefix_replayed_from_fresh_game": bool(prefix),
                  "rom_unchanged": before == hashlib.sha256(rom.read_bytes()).hexdigest(),
                  "oracle_used_by_gameplay": False, "whole_campaign_verified": False}
        (QA / "native_bomb_verification.json").write_text(json.dumps(report, indent=2) + "\n")
        if not report["rom_unchanged"] or any(case["mismatched_pixels"] for case in comparisons):
            raise RuntimeError("Bomb raster parity failed; inspect native_bomb_verification.json")
        print(f"BOMB_VERIFICATION_OK: {route['frames']} native Godot ticks; five missile door/bombs/Bomb Torizo/bomb placement; {sum(case['pixels'] for case in comparisons)} exact RGB pixels; ROM intact")


if __name__ == "__main__":
    main()
