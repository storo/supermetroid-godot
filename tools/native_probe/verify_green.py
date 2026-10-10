#!/usr/bin/env python3
"""Verify continuation from original Crateria SRAM into green Brinstar in Godot."""
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
    args = parser.parse_args()
    rom = ROOT / "rom_src/Super Metroid (Japan, USA) (En,Ja).sfc"
    before = hashlib.sha256(rom.read_bytes()).hexdigest()
    prefix = ROOT / "tools/native_probe/fixtures/station_prefix.inputs"
    manifest = json.loads(prefix.with_suffix(".json").read_text())
    data = prefix.read_bytes()
    if hashlib.sha256(data).hexdigest() != manifest["sha256"] or len(data) != manifest["frames"] * 2 or before != manifest["rom_sha256"]:
        raise RuntimeError("Recorded station input prefix or ROM does not match its manifest")
    with tempfile.TemporaryDirectory(prefix="sm-green-verify-") as directory:
        fixture = Path(directory)
        station = fixture / "station"
        station.mkdir()
        # Obtain a genuine original save by replaying normal inputs from boot;
        # never synthesize SRAM or restore game-memory snapshots.
        with (QA / "native_green_station_seed.log").open("w") as log:
            result = subprocess.run([str(ROOT / "native/build/sm_station_route"), str(rom), str(station), str(prefix)],
                                    cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=600)
        if result.returncode or "STATION_ROUTE_OK" not in (QA / "native_green_station_seed.log").read_text():
            raise RuntimeError("Failed to generate the original station save")
        seed = fixture / "seed.srm"
        shutil.copyfile(station / "station.srm", seed)
        seed_hash = hashlib.sha256(seed.read_bytes()).hexdigest()
        certified = json.loads((QA / "native_station_route.json").read_text())
        if seed.stat().st_size != 8192 or seed_hash != certified["sram_sha256"] or not certified["c_and_godot_sram_identical"]:
            raise RuntimeError("Station seed differs from the previously verified C/Godot save")
        with (QA / "native_green_controller.log").open("w") as log:
            result = subprocess.run([str(ROOT / "native/build/sm_green_route"), str(rom), directory, "--seed", str(seed)],
                                    cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=600)
        if result.returncode or "GREEN_ROUTE_OK" not in (QA / "native_green_controller.log").read_text():
            raise RuntimeError("Incomplete green Brinstar controller route")
        if hashlib.sha256(seed.read_bytes()).hexdigest() != seed_hash:
            raise RuntimeError("Controller modified the source SRAM")
        run([args.godot, "--path", str(ROOT), "--script", "tools/native_probe/green_test.gd", "--", "--route-fixture", directory],
            "native_green_godot.log", "GREEN_GODOT_OK", timeout=300)
        route = json.loads((QA / "native_green_route.json").read_text())
        required = {"loaded", "parlor", "pirates", "mushrooms", "elevator", "arrival", "control"}
        if set(route["captures"]) != required or route["room"] != 0x9ad9 or route["area"] != 1 or not route["green_movement"] or not route["saved_events_retained"]:
            raise RuntimeError("Incomplete original-save/elevator/Brinstar evidence")
        points = fixture / "checkpoints.csv"
        points.write_text("".join(f"{case['frame']},{name}\n" for name, case in sorted(route["captures"].items(), key=lambda item: item[1]["frame"])))
        oracle = fixture / "oracle"
        oracle.mkdir()
        run([str(ROOT / "native/build/sm_raster_oracle"), str(rom), str(oracle), str(fixture / "green.inputs"), str(points), str(seed)],
            "native_green_oracle.log", "RASTER_ORACLE_OK", timeout=300)
        cases = []
        for name, case in sorted(route["captures"].items()):
            expected = np.frombuffer((oracle / name / "frame.bgra").read_bytes(), np.uint8).reshape(224, 256, 4)[:, :, [2, 1, 0]]
            actual = np.asarray(Image.open(QA / f"native_green_{name}_original.png").convert("RGB"))
            if actual.shape != expected.shape:
                raise RuntimeError("Unexpected green Brinstar capture dimensions")
            error = np.abs(actual.astype(np.int16) - expected.astype(np.int16))
            Image.fromarray(expected).save(QA / f"native_green_{name}_oracle.png")
            cases.append({"name": name, **case, "pixels": 256 * 224,
                          "mismatched_pixels": int(np.any(error, axis=2).sum()), "max_channel_error": int(error.max())})
        intact = before == hashlib.sha256(rom.read_bytes()).hexdigest()
        seed_intact = seed_hash == hashlib.sha256(seed.read_bytes()).hexdigest()
        report = {"route": route, "cases": cases, "rom_unchanged": intact, "source_seed_unchanged": seed_intact,
                  "seed_generated_from_fresh_game_normal_inputs": True, "seed_matches_verified_station_sram": True,
                  "seed_is_original_sram_not_save_state": True, "oracle_used_by_gameplay": False,
                  "whole_campaign_verified": False}
        (QA / "native_green_verification.json").write_text(json.dumps(report, indent=2) + "\n")
        if not intact or not seed_intact or any(case["mismatched_pixels"] for case in cases):
            raise RuntimeError("Green Brinstar save/raster parity failed")
        print(f"GREEN_VERIFICATION_OK: {route['frames']} original saved-game Godot ticks; Crateria/Parlor/Terminator/pirates/mushrooms/elevator/green Brinstar control; {sum(case['pixels'] for case in cases)} exact RGB pixels; source SRAM and ROM intact")


if __name__ == "__main__":
    main()
