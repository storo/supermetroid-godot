#!/usr/bin/env python3
"""Verify the redrawn Ceres BG2 library in its three rooms and both states."""
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
    return np.asarray(Image.open(QA / f"native_ceres_art_{name}.png").convert("RGB"))


def different(a, b):
    return np.any(a != b, axis=2)


def mask(name):
    layers = np.asarray(Image.open(QA / f"native_ceres_art_{name}_layers.png").convert("RGBA"))
    eligible = (layers[:, :, 1] == 1) & (layers[:, :, 3] != 0) & (layers[:, :, 0] >= 81) & (layers[:, :, 0] <= 88)
    eligible[:32] = False
    return np.repeat(np.repeat(eligible, 2, axis=0), 2, axis=1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot")
    args = parser.parse_args()
    rom = ROOT / "rom_src/Super Metroid (Japan, USA) (En,Ja).sfc"
    before = hashlib.sha256(rom.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix="sm-ceres-art-verify-") as directory:
        fixture = Path(directory)
        run([str(ROOT / "native/build/sm_campaign_route"), str(rom), directory], "native_ceres_art_controller.log", "CAMPAIGN_ROUTE_OK")
        run([args.godot, "--path", str(ROOT), "--script", "tools/native_probe/ceres_art_test.gd", "--", "--route-fixture", directory],
            "native_ceres_art_godot.log", "CERES_ART_GODOT_OK", timeout=300)
        route = json.loads((QA / "native_ceres_art_route.json").read_text())
        required = {phase + room for phase in ("pre_", "escape_") for room in ("corridor", "stairs", "hall")}
        if set(route["captures"]) != required or not route["state_trace_matches"] or not route["presentation_leaves_core_unchanged"]:
            raise RuntimeError("Missing Ceres room/state evidence")
        points = fixture / "checkpoints.csv"
        points.write_text("".join(f"{case['frame']},{name}\n" for name, case in sorted(route["captures"].items(), key=lambda item: item[1]["frame"])))
        run([str(ROOT / "native/build/sm_raster_oracle"), str(rom), directory, str(fixture / "route.inputs"), str(points)],
            "native_ceres_art_oracle.log", "RASTER_ORACLE_OK")
        cases = []
        failures = []
        for name, case in sorted(route["captures"].items()):
            expected = np.frombuffer((fixture / name / "frame.bgra").read_bytes(), np.uint8).reshape(224, 256, 4)[:, :, [2, 1, 0]]
            original, restored = rgb(name + "_original"), rgb(name + "_restored")
            filtered, remastered = rgb(name + "_filtered"), rgb(name + "_remastered")
            if original.shape != expected.shape or filtered.shape != (448, 512, 3):
                raise RuntimeError("Unexpected render size: " + name)
            eligible = mask(name)
            changed = different(filtered, remastered)
            checks = {"name": name, **case, "pixels": 256 * 224,
                      "original_mismatched_pixels": int(different(original, expected).sum()),
                      "restored_mismatched_pixels": int(different(restored, expected).sum()),
                      "protected_pixels": int((~eligible).sum()),
                      "protected_mismatched_pixels": int((changed & ~eligible).sum()),
                      "eligible_bg2_pixels": int(eligible.sum()), "background_changed_pixels": int((changed & eligible).sum())}
            Image.fromarray(expected).save(QA / f"native_ceres_art_{name}_oracle.png")
            if any(value for key, value in checks.items() if "mismatched" in key):
                failures.append(name + ": pixel parity/protected layers")
            if name.startswith("pre_") and checks["background_changed_pixels"] < 1000:
                failures.append(name + ": no visible wall replacement")
            if checks["eligible_bg2_pixels"] > 1000 and checks["background_changed_pixels"] < 500:
                failures.append(name + ": visible background failed to change")
            cases.append(checks)
        filtered = rgb("pre_corridor_filtered")
        remastered = rgb("pre_corridor_remastered")
        eligible = mask("pre_corridor")
        fixture_checks = {"camera_only_mismatched_pixels": int(different(rgb("camera_only"), remastered).sum()),
                          "scroll_period_mismatched_pixels": int(different(rgb("scroll_period"), remastered).sum()),
                          "scroll_protected_mismatched_pixels": int((different(rgb("scroll_shift"), rgb("scroll_filtered")) & ~mask("scroll")).sum()),
                          "scroll_bg2_changed_pixels": int((different(rgb("scroll_shift"), remastered) & mask("scroll") & eligible).sum()),
                          "map_excluded_mismatched_pixels": int(different(rgb("map_excluded"), filtered).sum()),
                          "library_excluded_mismatched_pixels": int(different(rgb("library_excluded"), filtered).sum()),
                          "wrong_state_excluded_mismatched_pixels": int(different(rgb("wrong_state_excluded"), filtered).sum()),
                          "elevator_excluded_mismatched_pixels": int(different(rgb("elevator_excluded"), rgb("elevator_filtered")).sum()),
                          "fade_zero_mismatched_pixels": int(np.any(rgb("fade_zero") != 0, axis=2).sum()),
                          "forced_blank_mismatched_pixels": int(np.any(rgb("forced_blank") != 0, axis=2).sum()),
                          "palette_protected_mismatched_pixels": int((different(rgb("palette_flash"), rgb("palette_filtered")) & ~eligible).sum()),
                          "palette_bg2_changed_pixels": int((different(rgb("palette_flash"), remastered) & eligible).sum())}
        failures += [name for name, value in fixture_checks.items() if "mismatched" in name and value]
        if fixture_checks["palette_bg2_changed_pixels"] < 1000:
            failures.append("Native CGRAM flash did not affect the new art")
        if fixture_checks["scroll_bg2_changed_pixels"] < 1000:
            failures.append("Native BG2 scroll did not move the new wall")
        intact = before == hashlib.sha256(rom.read_bytes()).hexdigest()
        report = {"route": route, "cases": cases, "display_fixture_checks": fixture_checks,
                  "rom_unchanged": intact, "oracle_used_by_gameplay": False,
                  "whole_campaign_verified": False, "full_asset_redraw_complete": False}
        (QA / "native_ceres_art_verification.json").write_text(json.dumps(report, indent=2) + "\n")
        if failures or not intact:
            raise RuntimeError("Ceres art verification failed: " + "; ".join(failures))
        print(f"CERES_ART_VERIFICATION_OK: {route['frames']} fresh ticks; 3 rooms/2 states; {sum(case['pixels'] for case in cases)} exact original/restored RGB pixels; {sum(case['protected_pixels'] for case in cases)} protected pixels unchanged; native scroll/CGRAM/fade/selection; ROM intact")


if __name__ == "__main__":
    main()
