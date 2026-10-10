#!/usr/bin/env python3
"""Verify Big Pink lower missiles, bomb passage, Charge Beam and charged shot in Godot."""
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
    with tempfile.TemporaryDirectory(prefix="sm-charge-verify-") as directory:
        fixture = Path(directory)
        station = fixture / "station"
        station.mkdir()
        # Obtain a genuine original save by replaying normal inputs from boot;
        # never synthesize SRAM or restore game-memory snapshots.
        with (QA / "native_charge_station_seed.log").open("w") as log:
            result = subprocess.run([str(ROOT / "native/build/sm_station_route"), str(rom), str(station), str(prefix)],
                                    cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=600)
        if result.returncode or "STATION_ROUTE_OK" not in (QA / "native_charge_station_seed.log").read_text():
            raise RuntimeError("Failed to generate the original station save")
        seed = fixture / "seed.srm"
        shutil.copyfile(station / "station.srm", seed)
        seed_hash = hashlib.sha256(seed.read_bytes()).hexdigest()
        certified = json.loads((QA / "native_station_route.json").read_text())
        if seed.stat().st_size != 8192 or seed_hash != certified["sram_sha256"] or not certified["c_and_godot_sram_identical"]:
            raise RuntimeError("Station seed differs from the previously verified C/Godot save")
        with (QA / "native_charge_controller.log").open("w") as log:
            charge_prefix = ROOT / "tools/native_probe/fixtures/charge_prefix.inputs"
            charge_manifest = json.loads(charge_prefix.with_suffix(".json").read_text())
            if hashlib.sha256(charge_prefix.read_bytes()).hexdigest() != charge_manifest["sha256"] or charge_prefix.stat().st_size != charge_manifest["frames"] * 2 or seed_hash != charge_manifest["seed_sram_sha256"] or before != charge_manifest["rom_sha256"]:
                raise RuntimeError("Charge approach ancestry does not match")
            result = subprocess.run([str(ROOT / "native/build/sm_charge_route"), str(rom), directory, str(seed), str(charge_prefix)],
                                    cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=600)
        if result.returncode or "CHARGE_ROUTE_OK" not in (QA / "native_charge_controller.log").read_text():
            raise RuntimeError("Incomplete Charge Beam controller route")
        if hashlib.sha256(seed.read_bytes()).hexdigest() != seed_hash:
            raise RuntimeError("Controller modified the source SRAM")
        run([args.godot, "--path", str(ROOT), "--script", "tools/native_probe/charge_test.gd", "--", "--route-fixture", directory],
            "native_charge_godot.log", "CHARGE_GODOT_OK", timeout=300)
        route = json.loads((QA / "native_charge_route.json").read_text())
        required = {"arrival", "missile", "missile_notice", "bomb_passage", "alcove", "charge_item", "charge_notice", "charging", "charged_shot", "control"}
        if set(route["captures"]) != required or route["room"] != 0x9d19 or route["beams"] != 0x1000 or route["capacity"] != 10 or route["maximum_charge_counter"] < 60 or route["charged_projectile_frames"] < 1 or not route["saved_events_retained"]:
            raise RuntimeError("Incomplete original pickup/charge/projectile evidence")
        points = fixture / "checkpoints.csv"
        points.write_text("".join(f"{case['frame']},{name}\n" for name, case in sorted(route["captures"].items(), key=lambda item: item[1]["frame"])))
        oracle = fixture / "oracle"
        oracle.mkdir()
        run([str(ROOT / "native/build/sm_raster_oracle"), str(rom), str(oracle), str(fixture / "charge.inputs"), str(points), str(seed)],
            "native_charge_oracle.log", "RASTER_ORACLE_OK", timeout=300)
        cases = []
        for name, case in sorted(route["captures"].items()):
            expected = np.frombuffer((oracle / name / "frame.bgra").read_bytes(), np.uint8).reshape(224, 256, 4)[:, :, [2, 1, 0]]
            actual = np.asarray(Image.open(QA / f"native_charge_{name}_original.png").convert("RGB"))
            if actual.shape != expected.shape:
                raise RuntimeError("Unexpected Charge Beam capture dimensions")
            error = np.abs(actual.astype(np.int16) - expected.astype(np.int16))
            Image.fromarray(expected).save(QA / f"native_charge_{name}_oracle.png")
            cases.append({"name": name, **case, "pixels": 256 * 224,
                          "mismatched_pixels": int(np.any(error, axis=2).sum()), "max_channel_error": int(error.max())})
        intact = before == hashlib.sha256(rom.read_bytes()).hexdigest()
        seed_intact = seed_hash == hashlib.sha256(seed.read_bytes()).hexdigest()
        report = {"route": route, "cases": cases, "rom_unchanged": intact, "source_seed_unchanged": seed_intact,
                  "seed_generated_from_fresh_game_normal_inputs": True, "seed_matches_verified_station_sram": True,
                  "seed_is_original_sram_not_save_state": True, "oracle_used_by_gameplay": False,
                  "whole_campaign_verified": False, "spore_spawn_verified": False}
        (QA / "native_charge_verification.json").write_text(json.dumps(report, indent=2) + "\n")
        if not intact or not seed_intact or any(case["mismatched_pixels"] for case in cases):
            raise RuntimeError("Charge Beam save/raster parity failed")
        print(f"CHARGE_VERIFICATION_OK: {route['frames']} original saved-game Godot ticks; lower missiles, bomb passage, Charge Beam and charged projectile; {sum(case['pixels'] for case in cases)} exact RGB pixels; source SRAM and ROM intact")


if __name__ == "__main__":
    main()
