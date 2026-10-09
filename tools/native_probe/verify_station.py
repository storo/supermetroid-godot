#!/usr/bin/env python3
"""Verify the first energy tank and original station save/reload in Godot."""
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


def verify_seed_io(rom):
    """The oracle must reject malformed seeds and never write to a caller's save."""
    before = hashlib.sha256(rom.read_bytes()).hexdigest()
    cases = []
    with tempfile.TemporaryDirectory(prefix="sm-station-seed-") as directory:
        fixture = Path(directory)
        inputs = fixture / "one.inputs"
        inputs.write_bytes(bytes(2))
        points = fixture / "points.csv"
        points.write_text("1,probe\n")
        for size in (4097, 8192):
            seed = fixture / f"seed_{size}.srm"
            seed.write_bytes(bytes(size))
            seed_hash = hashlib.sha256(seed.read_bytes()).hexdigest()
            output = fixture / f"output_{size}"
            output.mkdir()
            result = subprocess.run([str(ROOT / "native/build/sm_raster_oracle"), str(rom), str(output), str(inputs), str(points), str(seed)],
                                    cwd=ROOT, capture_output=True, text=True, timeout=30)
            accepted = size == 8192
            expected = (result.returncode == 0 and "RASTER_ORACLE_OK" in result.stdout) if accepted else (result.returncode == 1 and "exactly 8192 bytes" in result.stderr)
            unchanged = seed_hash == hashlib.sha256(seed.read_bytes()).hexdigest()
            removed = not list(output.glob("oracle_*"))
            if not expected or not unchanged or not removed:
                raise RuntimeError("SRAM seed ownership/validation failed: " + result.stdout + result.stderr)
            cases.append({"seed_bytes": size, "exit": result.returncode, "accepted": accepted,
                          "seed_unchanged": unchanged, "private_copy_removed": removed})
    intact = before == hashlib.sha256(rom.read_bytes()).hexdigest()
    if not intact:
        raise RuntimeError("Seed test modified the ROM")
    (QA / "native_station_seed_io.json").write_text(json.dumps({"cases": cases, "rom_unchanged": intact, "whole_campaign_verified": False}, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot")
    default_prefix = ROOT / "tools/native_probe/fixtures/station_prefix.inputs"
    parser.add_argument("--input-prefix", type=Path, default=default_prefix, help="Ordinary controller trace from a fresh game to Crateria Save; never a save state")
    args = parser.parse_args()
    rom = ROOT / "rom_src/Super Metroid (Japan, USA) (En,Ja).sfc"
    before = hashlib.sha256(rom.read_bytes()).hexdigest()
    verify_seed_io(rom)
    if args.input_prefix.resolve() == default_prefix.resolve():
        manifest = json.loads(default_prefix.with_suffix(".json").read_text())
        data = default_prefix.read_bytes()
        if hashlib.sha256(data).hexdigest() != manifest["sha256"] or len(data) != manifest["frames"] * 2 or before != manifest["rom_sha256"]:
            raise RuntimeError("Recorded input prefix or ROM does not match its manifest")
    with tempfile.TemporaryDirectory(prefix="sm-station-verify-") as directory:
        fixture = Path(directory)
        with (QA / "native_station_controller.log").open("w") as log:
            result = subprocess.run([str(ROOT / "native/build/sm_station_route"), str(rom), directory, str(args.input_prefix.resolve())],
                                    cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=1800)
        if result.returncode or "STATION_ROUTE_OK" not in (QA / "native_station_controller.log").read_text():
            raise RuntimeError("Incomplete station controller route; inspect native_station_controller.log")
        run([args.godot, "--path", str(ROOT), "--script", "tools/native_probe/station_test.gd", "--", "--route-fixture", directory],
            "native_station_godot.log", "STATION_GODOT_OK", timeout=600)
        route = json.loads((QA / "native_station_route.json").read_text())
        required = {"exit", "barrier", "tank", "station", "saved", "loaded"}
        if (set(route["captures"]) != required or route["max_health"] != 199 or route["save_station"] != 1
                or route["sram_bytes"] != 8192 or not route["c_and_godot_sram_identical"]
                or not route["inventory_events_restored"] or not route["loaded_movement"]):
            raise RuntimeError("Incomplete energy/station/reload evidence")
        comparisons = []
        for loaded in (False, True):
            cases = {name: case for name, case in route["captures"].items() if (name == "loaded") == loaded}
            output = fixture / ("loaded_oracle" if loaded else "original_oracle")
            output.mkdir()
            points = output / "checkpoints.csv"
            points.write_text("".join(f"{case['frame']},{name}\n" for name, case in sorted(cases.items(), key=lambda pair: pair[1]["frame"])))
            command = [str(ROOT / "native/build/sm_raster_oracle"), str(rom), str(output),
                       str(fixture / ("reload.inputs" if loaded else "station.inputs")), str(points)]
            seed = fixture / "reload_seed.srm"
            seed_before = hashlib.sha256(seed.read_bytes()).hexdigest()
            if loaded:
                command.append(str(seed))
            run(command, "native_station_loaded_oracle.log" if loaded else "native_station_oracle.log", "RASTER_ORACLE_OK", timeout=600)
            if seed_before != hashlib.sha256(seed.read_bytes()).hexdigest():
                raise RuntimeError("Oracle modified the original SRAM seed")
            for name, case in sorted(cases.items()):
                expected = np.frombuffer((output / name / "frame.bgra").read_bytes(), np.uint8).reshape(224, 256, 4)[:, :, [2, 1, 0]]
                actual = np.asarray(Image.open(QA / f"native_station_{name}_original.png").convert("RGB"))
                if actual.shape != expected.shape:
                    raise RuntimeError(f"Unexpected image shape for {name}: {actual.shape}")
                error = np.abs(actual.astype(np.int16) - expected.astype(np.int16))
                Image.fromarray(expected).save(QA / f"native_station_{name}_oracle.png")
                comparisons.append({"name": name, "frame": case["frame"], "pixels": 256 * 224,
                                    "mismatched_pixels": int(np.any(error, axis=2).sum()), "max_channel_error": int(error.max())})
        report = {"route": route, "pixel_comparisons": comparisons, "prefix_replayed_from_fresh_game": True,
                  "oracle_seed_unchanged": True, "rom_unchanged": before == hashlib.sha256(rom.read_bytes()).hexdigest(),
                  "oracle_used_by_gameplay": False, "whole_campaign_verified": False}
        (QA / "native_station_verification.json").write_text(json.dumps(report, indent=2) + "\n")
        if not report["rom_unchanged"] or any(case["mismatched_pixels"] for case in comparisons):
            raise RuntimeError("Station raster parity failed; inspect native_station_verification.json")
        print(f"STATION_VERIFICATION_OK: {route['frames']} fresh-game Godot ticks, energy tank/station/identical SRAM/close-reopen persistence; {sum(case['pixels'] for case in comparisons)} exact RGB pixels; ROM intact")


if __name__ == "__main__":
    main()
