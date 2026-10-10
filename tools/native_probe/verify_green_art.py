#!/usr/bin/env python3
"""Verify redrawn Green Brinstar BG2 tiles, native mapping and protected layers."""
import argparse
import hashlib
import json
import shutil
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image
from verify_raster import ROOT, QA, run


PREFIX = "native_green_art_"


def rgb(name):
    return np.asarray(Image.open(QA / f"{PREFIX}{name}.png").convert("RGB"))


def layers(name, sub=False):
    return np.asarray(Image.open(QA / f"{PREFIX}{name}_{'sub_' if sub else ''}layers.png").convert("RGBA"))


def different(a, b):
    return np.any(a != b, axis=2)


def mask(name):
    data = layers(name)
    eligible = (data[:, :, 1] == 1) & (data[:, :, 3] != 0) & (data[:, :, 0] >= 113) & (data[:, :, 0] <= 127)
    eligible[:32] = False
    return eligible.repeat(2, axis=0).repeat(2, axis=1)


def scaled_metadata(data):
    # Independent Scale2x selection matching the declared rendering algorithm.
    edge = np.pad(data, ((1, 1), (1, 1), (0, 0)), mode="edge")
    e, b, d, f, h = data, edge[:-2, 1:-1], edge[1:-1, :-2], edge[1:-1, 2:], edge[2:, 1:-1]
    result = e.repeat(2, 0).repeat(2, 1)
    valid = different(b, h) & different(d, f)
    for yy, xx, a, other in [(0, 0, d, b), (0, 1, b, f), (1, 0, d, h), (1, 1, h, f)]:
        selected = valid & ~different(a, other)
        result[yy::2, xx::2][selected] = a[selected]
    return result


def atlas_lookup_check(name, fixture, filtered_name, remastered_name):
    """Check actual GPU texels against an independent native tile/flip lookup.

    Native color math uses the original subscreen; the final image retains its
    18% original contribution. Two RGB levels allow shader/PNG rounding only.
	"""
    metadata_name = "control" if name == "palette_flash" else name
    data = layers(metadata_name)
    selected = scaled_metadata(data)
    sub = scaled_metadata(layers(metadata_name, True))
    center = data.repeat(2, 0).repeat(2, 1)
    raster = np.frombuffer((fixture / "art_packets" / f"{name}.raster").read_bytes(), np.uint8).reshape(256, 1024)
    vram = np.frombuffer((fixture / "art_packets" / f"{name}.vram").read_bytes(), "<u2")
    y, x = np.indices((448, 512))
    row, column = y // 2, x // 2
    def word(offset):
        return raster[row, offset].astype(np.int32) | (raster[row, offset + 1].astype(np.int32) << 8)
    mx = (column + word(44)) & 1023
    my = (row + 1 + word(46)) & 1023
    address = (word(40) + ((my >> 3) & 31) * 32 + ((mx >> 3) & 31) + np.where(((mx >> 3) & 32) != 0, 1024, 0)) & 32767
    tile_word = vram[address].astype(np.int32)
    number = tile_word & 1023
    supported = ((number >= 236) & (number <= 239)) | ((number >= 252) & (number <= 255)) | ((number >= 291) & (number <= 303)) | ((number >= 307) & (number <= 351))
    eligible = mask(metadata_name) & ~different(selected, center) & supported & (((tile_word >> 10) & 7) == 7)
    eligible &= (raster[row, 80] == 0) & (raster[row, 81] == 0) & (raster[row, 3] == 0)
    eligible &= np.all(rgb(filtered_name) < 250, axis=2)
    atlas = np.asarray(Image.open(ROOT / "assets/remastered/green_bg2_tiles.png").convert("RGB"), dtype=np.float64) / 255
    height, width = atlas.shape[:2]
    local_x, local_y = (mx & 7) + (x % 2 + .5) / 2, (my & 7) + (y % 2 + .5) / 2
    local_x = np.where((tile_word & 0x4000) != 0, 8 - local_x, local_x)
    local_y = np.where((tile_word & 0x8000) != 0, 8 - local_y, local_y)
    local_x, local_y = np.clip(local_x, 64 / width, 8 - 64 / width), np.clip(local_y, 32 / height, 8 - 32 / height)
    sx = ((number % 16) * 8 + local_x) / 128 * width - .5
    sy = ((number // 16 - 14) * 8 + local_y) / 64 * height - .5
    sx, sy = np.clip(sx, 0, width - 1), np.clip(sy, 0, height - 1)
    ix, iy = np.floor(sx).astype(int), np.floor(sy).astype(int)
    fx, fy = (sx - ix)[..., None], (sy - iy)[..., None]
    jx, jy = np.minimum(ix + 1, width - 1), np.minimum(iy + 1, height - 1)
    sampled = (atlas[iy, ix] * (1 - fx) + atlas[iy, jx] * fx) * (1 - fy) + (atlas[jy, ix] * (1 - fx) + atlas[jy, jx] * fx) * fy
    palette = raster[:, 256:768].copy().view("<u2").reshape(256, 256)
    def color5(index):
        value = palette[row, index]
        return np.stack([(value >> shift) & 31 for shift in (0, 5, 10)], axis=2).astype(float)
    manifest = json.loads((ROOT / "assets/extracted/references/green_bg2_tiles_original.json").read_text())
    reference = np.zeros((256, 3))
    for index, value in manifest["palette_rgb5"].items():
        reference[int(index)] = value
    color = np.clip(sampled * 31 + color5(selected[:, :, 0]) - reference[selected[:, :, 0]], 0, 31)
    flags = raster[row, 82]
    sub_layer = np.where(sub[:, :, 3] == 0, 5, sub[:, :, 1])
    use_sub = ((flags & 1) != 0) & (sub_layer != 5)
    other = np.where(use_sub[..., None], color5(sub[:, :, 0]), raster[row, 84:87].astype(float))
    math = (raster[row, 83] & 2) != 0
    combined = np.where(((flags & 2) != 0)[..., None], color - other, color + other)
    halve = ((flags & 4) != 0) & (((flags & 1) == 0) | (sub_layer != 5))
    combined = np.where(halve[..., None], combined * .5, combined)
    color = np.where(math[..., None], np.clip(combined, 0, 31), color)
    color = color / 31 * (raster[row, 2].astype(float) / 15)[..., None]
    expected = np.rint((.18 * rgb(filtered_name).astype(float) / 255 + .82 * color) * 255).clip(0, 255)
    error = np.abs(expected - rgb(remastered_name))[eligible]
    checked = int(eligible.sum())
    if checked < 10000 or (error.size and error.max() > 2):
        raise RuntimeError(f"Independent atlas lookup failed: {name}, pixels={checked}, error={error.max() if error.size else -1}")
    return {"name": name, "checked_pixels": checked, "max_channel_error": int(error.max()), "allowed_rounding_error": 2}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot")
    args = parser.parse_args()
    rom = ROOT / "rom_src/Super Metroid (Japan, USA) (En,Ja).sfc"
    before = hashlib.sha256(rom.read_bytes()).hexdigest()
    prefix = ROOT / "tools/native_probe/fixtures/station_prefix.inputs"
    manifest = json.loads(prefix.with_suffix(".json").read_text())
    if hashlib.sha256(prefix.read_bytes()).hexdigest() != manifest["sha256"] or prefix.stat().st_size != manifest["frames"] * 2 or before != manifest["rom_sha256"]:
        raise RuntimeError("Original station input ancestry does not match")
    with tempfile.TemporaryDirectory(prefix="sm-green-art-verify-") as directory:
        fixture = Path(directory)
        station = fixture / "station"
        station.mkdir()
        run([str(ROOT / "native/build/sm_station_route"), str(rom), str(station), str(prefix)], "native_green_art_station.log", "STATION_ROUTE_OK", 600)
        seed = fixture / "seed.srm"
        shutil.copyfile(station / "station.srm", seed)
        seed_hash = hashlib.sha256(seed.read_bytes()).hexdigest()
        certified = json.loads((QA / "native_station_route.json").read_text())
        if seed.stat().st_size != 8192 or seed_hash != certified["sram_sha256"] or not certified["c_and_godot_sram_identical"]:
            raise RuntimeError("SRAM differs from the certified original save")
        run([str(ROOT / "native/build/sm_green_route"), str(rom), directory, "--seed", str(seed)], "native_green_art_controller.log", "GREEN_ROUTE_OK", 600)
        run([args.godot, "--path", str(ROOT), "--script", "tools/native_probe/green_art_test.gd", "--", "--route-fixture", directory], "native_green_art_godot.log", "GREEN_GODOT_OK", 300)
        route = json.loads((QA / "native_green_art_route.json").read_text())
        captures = route["captures"] | route["additional_art_captures"]
        if len(captures) != 9 or not route["state_trace_matches"] or not all(c["presentation_leaves_core_unchanged"] for c in captures.values()):
            raise RuntimeError("Incomplete native state/camera evidence")
        points = fixture / "checkpoints.csv"
        points.write_text("".join(f"{case['frame']},{name}\n" for name, case in sorted(captures.items(), key=lambda item: item[1]["frame"])))
        oracle = fixture / "oracle"
        oracle.mkdir()
        run([str(ROOT / "native/build/sm_raster_oracle"), str(rom), str(oracle), str(fixture / "green.inputs"), str(points), str(seed)], "native_green_art_oracle.log", "RASTER_ORACLE_OK", 300)
        cases, failures = [], []
        for name, case in sorted(captures.items()):
            expected = np.frombuffer((oracle / name / "frame.bgra").read_bytes(), np.uint8).reshape(224, 256, 4)[:, :, [2, 1, 0]]
            original, restored = rgb(name + "_original"), rgb(name + "_restored")
            eligible = mask(name)
            changed = different(rgb(name + "_filtered"), rgb(name + "_remastered"))
            Image.fromarray(expected).save(QA / f"{PREFIX}{name}_oracle.png")
            check = {"name": name, **case, "pixels": 57344, "original_mismatched_pixels": int(different(original, expected).sum()),
                     "restored_mismatched_pixels": int(different(restored, expected).sum()), "protected_pixels": int((~eligible).sum()),
                     "protected_mismatched_pixels": int((changed & ~eligible).sum()), "eligible_bg2_pixels": int(eligible.sum()),
                     "background_changed_pixels": int((changed & eligible).sum())}
            if any(value for key, value in check.items() if "mismatched" in key):
                failures.append(name + ": original restoration/protected layers")
            if name in {"control", "wall_upper", "wall_middle"} and check["background_changed_pixels"] < 1000:
                failures.append(name + ": wall art absent")
            cases.append(check)
        filtered, remastered, eligible = rgb("control_filtered"), rgb("control_remastered"), mask("control")
        checks = {"camera_only_mismatched_pixels": int(different(rgb("camera_only"), remastered).sum()),
                  "scroll_period_mismatched_pixels": int(different(rgb("scroll_period"), remastered).sum()),
                  "fade_zero_mismatched_pixels": int(np.any(rgb("fade_zero") != 0, axis=2).sum()),
                  "forced_blank_mismatched_pixels": int(np.any(rgb("forced_blank") != 0, axis=2).sum())}
        for excluded in ("map", "room", "state"):
            checks[excluded + "_excluded_mismatched_pixels"] = int(different(rgb(excluded + "_excluded"), filtered).sum())
        for name in ("scroll_shift", "palette_flash", "tile_flip", "tile_remap"):
            protected = eligible if name == "palette_flash" else mask(name)
            changed = different(rgb(name), rgb(name + "_filtered"))
            checks[name + "_protected_mismatched_pixels"] = int((changed & ~protected).sum())
            checks[name + "_bg2_changed_pixels"] = int((different(rgb(name), remastered) & protected & eligible).sum())
            if checks[name + "_bg2_changed_pixels"] < 1000:
                failures.append(name + ": native map/scroll/palette not reflected")
        failures += [name for name, value in checks.items() if "mismatched" in name and value]
        lookups = [atlas_lookup_check("control", fixture, "control_filtered", "control_remastered")]
        for name in ("tile_flip", "tile_remap", "palette_flash"):
            lookups.append(atlas_lookup_check(name, fixture, name + "_filtered", name))
        intact = before == hashlib.sha256(rom.read_bytes()).hexdigest()
        seed_intact = seed_hash == hashlib.sha256(seed.read_bytes()).hexdigest()
        report = {"route": route, "cases": cases, "display_fixture_checks": checks, "independent_atlas_lookups": lookups,
                  "rom_unchanged": intact, "source_seed_unchanged": seed_intact,
                  "seed_generated_from_fresh_game_normal_inputs": True, "seed_matches_verified_station_sram": True,
                  "oracle_used_by_gameplay": False, "whole_campaign_verified": False, "full_asset_redraw_complete": False}
        (QA / f"{PREFIX}verification.json").write_text(json.dumps(report, indent=2) + "\n")
        if failures or not intact or not seed_intact:
            raise RuntimeError("Green art verification failed: " + "; ".join(failures))
        print(f"GREEN_ART_VERIFICATION_OK: {route['frames']} original saved-game ticks; 66 BG2 tiles; {sum(c['pixels'] for c in cases)} exact original/restored RGB pixels; {sum(c['protected_pixels'] for c in cases)} protected pixels unchanged; native atlas IDs/flips/scroll/CGRAM; ROM/SRAM intact")


if __name__ == "__main__":
    main()
