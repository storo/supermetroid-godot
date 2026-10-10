#!/usr/bin/env python3
"""Verify the ordinary-input return from Charge Beam with native wall jumps."""
import argparse
import hashlib
import json
import shutil
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image
from verify_raster import ROOT, QA, run


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot")
    args = parser.parse_args()
    rom = ROOT / "rom_src/Super Metroid (Japan, USA) (En,Ja).sfc"
    before = sha(rom)
    station_prefix = ROOT / "tools/native_probe/fixtures/station_prefix.inputs"
    station_manifest = json.loads(station_prefix.with_suffix(".json").read_text())
    if sha(station_prefix) != station_manifest["sha256"] or station_prefix.stat().st_size != station_manifest["frames"] * 2 or before != station_manifest["rom_sha256"]:
        raise RuntimeError("Station input/ROM ancestry does not match")
    prefix = ROOT / "tools/native_probe/fixtures/pink_ascent_prefix.inputs"
    manifest = json.loads(prefix.with_suffix(".json").read_text())
    if sha(prefix) != manifest["sha256"] or prefix.stat().st_size != manifest["frames"] * 2 or before != manifest["rom_sha256"]:
        raise RuntimeError("Certified Charge Beam input/ROM ancestry does not match")
    with tempfile.TemporaryDirectory(prefix="sm-pink-ascent-verify-") as directory:
        fixture = Path(directory)
        station = fixture / "station"
        station.mkdir()
        run([str(ROOT / "native/build/sm_station_route"), str(rom), str(station), str(station_prefix)], "native_pink_ascent_station_seed.log", "STATION_ROUTE_OK", 600)
        seed = fixture / "seed.srm"
        shutil.copyfile(station / "station.srm", seed)
        seed_hash = sha(seed)
        certified = json.loads((QA / "native_station_route.json").read_text())
        if seed.stat().st_size != 8192 or seed_hash != certified["sram_sha256"] or seed_hash != manifest["seed_sram_sha256"] or not certified["c_and_godot_sram_identical"]:
            raise RuntimeError("SRAM differs from the certified original station save")
        run([str(ROOT / "native/build/sm_pink_ascent_route"), str(rom), directory, str(seed), str(prefix)], "native_pink_ascent_controller.log", "PINK_ASCENT_ROUTE_OK", 300)
        if sha(seed) != seed_hash:
            raise RuntimeError("Ascent controller modified the source SRAM")
        run([args.godot, "--path", str(ROOT), "--script", "tools/native_probe/pink_ascent_test.gd", "--", "--route-fixture", directory], "native_pink_ascent_godot.log", "PINK_ASCENT_GODOT_OK", 300)
        route = json.loads((QA / "native_pink_ascent_route.json").read_text())
        names = {"alcove_control", "normal_jump", "wall_first", "wall_third", "top_platform", "tunnel_morph", "exit_standing", "control"}
        if set(route["captures"]) != names or route["frames"] != 10503 or route["columns_compared_per_tick"] != 29 or len(route["wall_jumps"]) != 3 or route["wall_jump_frames"] != 6 or not route["standing_movement_after_exit"] or not route["health_and_equipment_retained_during_ascent"]:
            raise RuntimeError("Incomplete wall-jump/passage/control evidence")
        points = fixture / "checkpoints.csv"
        points.write_text("".join(f"{case['frame']},{name}\n" for name, case in sorted(route["captures"].items(), key=lambda item: item[1]["frame"])))
        oracle = fixture / "oracle"
        oracle.mkdir()
        run([str(ROOT / "native/build/sm_raster_oracle"), str(rom), str(oracle), str(fixture / "ascent.inputs"), str(points), str(seed)], "native_pink_ascent_oracle.log", "RASTER_ORACLE_OK", 300)
        cases = []
        for name, case in sorted(route["captures"].items()):
            expected = np.frombuffer((oracle / name / "frame.bgra").read_bytes(), np.uint8).reshape(224, 256, 4)[:, :, [2, 1, 0]]
            actual = np.asarray(Image.open(QA / f"native_pink_ascent_{name}_original.png").convert("RGB"))
            if actual.shape != expected.shape:
                raise RuntimeError("Unexpected ascent capture dimensions")
            error = np.abs(actual.astype(np.int16) - expected.astype(np.int16))
            Image.fromarray(expected).save(QA / f"native_pink_ascent_{name}_oracle.png")
            cases.append({"name": name, **case, "pixels": 57344,
                          "mismatched_pixels": int(np.any(error, axis=2).sum()), "max_channel_error": int(error.max())})
        intact, seed_intact = sha(rom) == before, sha(seed) == seed_hash
        report = {"route": route, "cases": cases, "rom_unchanged": intact, "source_seed_unchanged": seed_intact,
                  "seed_generated_from_fresh_game_normal_inputs": True, "seed_matches_verified_station_sram": True,
                  "seed_is_original_sram_not_save_state": True, "controller_uses_only_normal_joypad_inputs": True,
                  "oracle_used_by_gameplay": False, "whole_campaign_verified": False, "spore_spawn_verified": False}
        (QA / "native_pink_ascent_verification.json").write_text(json.dumps(report, indent=2) + "\n")
        if not intact or not seed_intact or any(case["mismatched_pixels"] or not case["presentation_leaves_core_unchanged"] for case in cases):
            raise RuntimeError("Ascent source/render/state parity failed")
        print(f"PINK_ASCENT_VERIFICATION_OK: {route['frames']} native Godot ticks, 29 fields per tick; three wall jumps, Morph passage and stable standing control; {sum(case['pixels'] for case in cases)} exact RGB pixels; health/ammo/events and source ROM/SRAM intact")


if __name__ == "__main__":
    main()
