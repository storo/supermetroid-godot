#!/usr/bin/env python3
"""Verify the 44 redrawn Parlor BG2 cells in both original room states."""
import argparse
import hashlib
import json
import shutil
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image
from verify_raster import ROOT, QA, run


PREFIX = "native_parlor_art_"


def rgb(name):
    return np.asarray(Image.open(QA / f"{PREFIX}{name}.png").convert("RGB"))


def layers(name, sub=False):
    return np.asarray(Image.open(QA / f"{PREFIX}{name}_{'sub_' if sub else ''}layers.png").convert("RGBA"))


def different(a, b):
    return np.any(a != b, axis=2)


def mask(name):
    data = layers(name)
    eligible = (data[:, :, 1] == 1) & (data[:, :, 3] != 0) & (data[:, :, 0] >= 65) & (data[:, :, 0] <= 79)
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
    metadata_name = "awake_upper" if name == "palette_flash" else name
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
    supported = ((number >= 200) & (number <= 255) & ((number % 16) >= 8)) | ((number >= 490) & (number <= 511) & ((number % 16) >= 10))
    eligible = mask(metadata_name) & ~different(selected, center) & supported & (((tile_word >> 10) & 7) == 4)
    eligible &= (raster[row, 80] == 0) & (raster[row, 81] == 0) & (raster[row, 3] == 0)
    eligible &= np.all(rgb(filtered_name) < 250, axis=2)
    atlas = np.asarray(Image.open(ROOT / "assets/remastered/parlor_bg2_tiles.png").convert("RGB"), dtype=np.float64) / 255
    height, width = atlas.shape[:2]
    local_x, local_y = (mx & 7) + (x % 2 + .5) / 2, (my & 7) + (y % 2 + .5) / 2
    local_x = np.where((tile_word & 0x4000) != 0, 8 - local_x, local_x)
    local_y = np.where((tile_word & 0x8000) != 0, 8 - local_y, local_y)
    local_x, local_y = np.clip(local_x, 32 / width, 8 - 32 / width), np.clip(local_y, 24 / height, 8 - 24 / height)
    sx = (np.where(number < 256, number % 16 - 8, number % 16 - 10) * 8 + local_x) / 64 * width - .5
    sy = (np.where(number < 256, number // 16 - 12, number // 16 - 26) * 8 + local_y) / 48 * height - .5
    sx, sy = np.clip(sx, 0, width - 1), np.clip(sy, 0, height - 1)
    ix, iy = np.floor(sx).astype(int), np.floor(sy).astype(int)
    fx, fy = (sx - ix)[..., None], (sy - iy)[..., None]
    jx, jy = np.minimum(ix + 1, width - 1), np.minimum(iy + 1, height - 1)
    sampled = (atlas[iy, ix] * (1 - fx) + atlas[iy, jx] * fx) * (1 - fy) + (atlas[jy, ix] * (1 - fx) + atlas[jy, jx] * fx) * fy
    palette = raster[:, 256:768].copy().view("<u2").reshape(256, 256)
    def color5(index):
        value = palette[row, index]
        return np.stack([(value >> shift) & 31 for shift in (0, 5, 10)], axis=2).astype(float)
    manifest = json.loads((ROOT / "assets/extracted/references/parlor_bg2_tiles_original.json").read_text())
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
    return {"name": name, "checked_pixels": checked, "max_channel_error": int(error.max()), "allowed_rounding_error": 2,
            "checked_tile_ids": sorted(map(int, np.unique(number[eligible]))),
            "checked_flip_modes": sorted(map(int, np.unique((tile_word[eligible] >> 14) & 3)))}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(fixture, seed=None):
    rom = ROOT / "rom_src/Super Metroid (Japan, USA) (En,Ja).sfc"
    prefix = ROOT / "tools/native_probe/fixtures/station_prefix.inputs"
    manifest = json.loads(prefix.with_suffix(".json").read_text())
    if sha(prefix) != manifest["sha256"] or prefix.stat().st_size != manifest["frames"] * 2 or sha(rom) != manifest["rom_sha256"]:
        raise RuntimeError("Station prefix/ROM ancestry does not match")
    asset = ROOT / "assets/remastered/parlor_bg2_tiles.png"
    reference = ROOT / "assets/extracted/references/parlor_bg2_tiles_original.png"
    provenance = json.loads(asset.with_suffix(".json").read_text())
    extracted = json.loads(reference.with_suffix(".json").read_text())
    if sha(asset) != provenance["asset_sha256"] or sha(reference) != provenance["reference_sha256"] or sha(reference) != extracted["png_sha256"] or len(extracted["used_tiles"]) != 44 or extracted["rom_sha256"] != sha(rom):
        raise RuntimeError("Parlor atlas/reference provenance does not match")
    if seed is None:
        station = fixture / "station"
        station.mkdir()
        run([str(ROOT / "native/build/sm_station_route"), str(rom), str(station), str(prefix)], "native_parlor_art_station.log", "STATION_ROUTE_OK", 600)
        seed = station / "station.srm"
    shutil.copyfile(seed, fixture / "seed.srm")
    seed = fixture / "seed.srm"
    certificate = json.loads((QA / "native_station_route.json").read_text())
    if seed.stat().st_size != 8192 or sha(seed) != certificate["sram_sha256"] or not certificate["c_and_godot_sram_identical"]:
        raise RuntimeError("Original SRAM differs from certified C/Godot save")
    run([str(ROOT / "native/build/sm_green_route"), str(rom), str(fixture), "--seed", str(seed)], "native_parlor_art_controller.log", "GREEN_ROUTE_OK", 600)
    (fixture / "dormant.inputs").write_bytes(prefix.read_bytes()[:18117 * 2])
    jobs = []
    for name, inputs, points, has_seed in [
            ("dormant", "dormant.inputs", [(17693, "dormant_entry"), (17967, "dormant_middle"), (18117, "dormant_lower")], False),
            ("awake", "green.inputs", [(1444, "awake_lower"), (1598, "awake_middle"), (1813, "awake_upper"), (2180, "awake_gate")], True)]:
        oracle = fixture / (name + "_oracle")
        oracle.mkdir()
        checkpoints = fixture / (name + "_checkpoints.csv")
        checkpoints.write_text("".join(f"{frame},{label}\n" for frame, label in points))
        command = [str(ROOT / "native/build/sm_raster_oracle"), str(rom), str(oracle), str(fixture / inputs), str(checkpoints)]
        if has_seed:
            command.append(str(seed))
        run(command, "native_parlor_art_" + name + "_oracle.log", "RASTER_ORACLE_OK", 300)
        cases = json.loads((oracle / "cases.json").read_text())
        if len(cases) != len(points) or any(case["state"] != 8 or case["room"] != 0x92fd or case["room_state"] != (0x932e if has_seed else 0x9314) for case in cases):
            raise RuntimeError("Missing actual Parlor state/camera cases")
        job = {"name": name, "inputs": inputs, "oracle": oracle.name, "cases": cases}
        if has_seed:
            job.update(seed="seed.srm", trace="green.csv")
        jobs.append(job)
    (fixture / "runs.json").write_text(json.dumps(jobs, indent=2) + "\n")
    return jobs


def verify(fixture, jobs, godot, fresh_seed):
    rom = ROOT / "rom_src/Super Metroid (Japan, USA) (En,Ja).sfc"
    before, seed_hash = sha(rom), sha(fixture / "seed.srm")
    run([godot, "--path", str(ROOT), "--script", "tools/native_probe/parlor_art_test.gd", "--", "--route-fixture", str(fixture)], "native_parlor_art_godot.log", "PARLOR_ART_GODOT_OK", 300)
    route = json.loads((QA / "native_parlor_art_route.json").read_text())
    if route["frames"] != 23433 or route["trace_frames"] != 5316 or len(route["captures"]) != 7:
        raise RuntimeError("Incomplete Parlor state/input coverage")
    cases, failures = [], []
    for job in jobs:
        for case in job["cases"]:
            name = case["name"]
            expected = np.frombuffer((fixture / job["oracle"] / name / "frame.bgra").read_bytes(), np.uint8).reshape(224, 256, 4)[:, :, [2, 1, 0]]
            eligible = mask(name)
            changed = different(rgb(name + "_filtered"), rgb(name + "_remastered"))
            Image.fromarray(expected).save(QA / f"{PREFIX}{name}_oracle.png")
            check = {**case, "pixels": 57344,
                     "original_mismatched_pixels": int(different(rgb(name + "_original"), expected).sum()),
                     "restored_mismatched_pixels": int(different(rgb(name + "_restored"), expected).sum()),
                     "protected_pixels": int((~eligible).sum()), "protected_mismatched_pixels": int((changed & ~eligible).sum()),
                     "eligible_bg2_pixels": int(eligible.sum()), "background_changed_pixels": int((changed & eligible).sum()),
                     "presentation_leaves_core_unchanged": route["captures"][name]["presentation_leaves_core_unchanged"]}
            if any(value for key, value in check.items() if "mismatched" in key) or not check["presentation_leaves_core_unchanged"]:
                failures.append(name + ": original/restored/protected/state parity")
            if check["background_changed_pixels"] < 1000:
                failures.append(name + ": new background absent")
            cases.append(check)
    filtered, remastered, eligible = rgb("awake_upper_filtered"), rgb("awake_upper_remastered"), mask("awake_upper")
    checks = {"camera_only_mismatched_pixels": int(different(rgb("camera_only"), remastered).sum()),
              "scroll_period_mismatched_pixels": int(different(rgb("scroll_period"), remastered).sum()),
              "fade_zero_mismatched_pixels": int(np.any(rgb("fade_zero") != 0, axis=2).sum()),
              "forced_blank_mismatched_pixels": int(np.any(rgb("forced_blank") != 0, axis=2).sum())}
    for excluded in ("map", "room", "state", "endgame"):
        checks[excluded + "_excluded_mismatched_pixels"] = int(different(rgb(excluded + "_excluded"), filtered).sum())
    for name in ("scroll_shift", "palette_flash", "tile_flip", "tile_remap"):
        protected = eligible if name == "palette_flash" else mask(name)
        changed = different(rgb(name), rgb(name + "_filtered"))
        checks[name + "_protected_mismatched_pixels"] = int((changed & ~protected).sum())
        checks[name + "_bg2_changed_pixels"] = int((different(rgb(name), remastered) & protected & eligible).sum())
        if checks[name + "_bg2_changed_pixels"] < 1000:
            failures.append(name + ": native map/scroll/palette not reflected")
    failures += [name for name, value in checks.items() if "mismatched" in name and value]
    lookups = [atlas_lookup_check(name, fixture, name + "_filtered", name + "_remastered") for name in ("awake_upper", "dormant_entry", "dormant_middle")]
    lookups += [atlas_lookup_check(name, fixture, name + "_filtered", name) for name in ("tile_flip", "tile_remap", "palette_flash")]
    remapped = next(check for check in lookups if check["name"] == "tile_remap")
    source = json.loads((ROOT / "assets/extracted/references/parlor_bg2_tiles_original.json").read_text())
    if remapped["checked_tile_ids"] != source["used_tiles"] or remapped["checked_flip_modes"] != [0, 1, 2, 3]:
        raise RuntimeError("Independent sampling does not cover all 44 IDs/four flips")
    intact, seed_intact = sha(rom) == before, sha(fixture / "seed.srm") == seed_hash
    report = {"route": route, "cases": cases, "display_fixture_checks": checks, "independent_atlas_lookups": lookups,
              "rom_unchanged": intact, "source_seed_unchanged": seed_intact,
              "seed_generated_from_fresh_game_normal_inputs": fresh_seed, "seed_matches_verified_station_sram": True,
              "oracle_used_by_gameplay": False, "whole_campaign_verified": False, "full_asset_redraw_complete": False,
              "endgame_parlor_state_verified": False, "other_crateria_rocks_rooms_verified": False}
    (QA / f"{PREFIX}verification.json").write_text(json.dumps(report, indent=2) + "\n")
    if failures or not intact or not seed_intact:
        raise RuntimeError("Parlor art verification failed: " + "; ".join(failures))
    print(f"PARLOR_ART_VERIFICATION_OK: {route['frames']} native ticks, 5316 with full 25-field C/Godot parity; 44 tiles in two original Parlor states; {sum(c['pixels'] for c in cases)} exact original/restored RGB pixels; {sum(c['protected_pixels'] for c in cases)} protected pixels unchanged; native IDs/flips/scroll/CGRAM; ROM/SRAM intact")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="sm-parlor-art-verify-") as directory:
        fixture = Path(directory)
        jobs = prepare(fixture)
        verify(fixture, jobs, args.godot, True)



if __name__ == "__main__":
    main()
