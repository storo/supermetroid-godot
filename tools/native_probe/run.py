#!/usr/bin/env python3
"""Run the research probe with temporary SRAM and validate actual completion."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ROM = ROOT / "rom_src/Super Metroid (Japan, USA) (En,Ja).sfc"
expected = "12b77c4bc9c1832cee8881244659065ee1d84c70c3d29e6eaf92e6798cc2ca72"
if hashlib.sha256(ROM.read_bytes()).hexdigest() != expected:
    raise SystemExit("Unexpected local ROM digest")
with tempfile.TemporaryDirectory(prefix="sm_native_probe_") as directory:
    (Path(directory) / "saves").mkdir()
    result = subprocess.run([str(Path(__file__).with_name("build") / "native_probe"), str(ROM)], cwd=directory, capture_output=True, text=True, timeout=60)
log = result.stdout + result.stderr
(ROOT / "docs/qa/native_probe.log").write_text(log)
print("\n".join(line for line in log.splitlines() if line.startswith("NATIVE_")))
if result.returncode or "NATIVE_PROBE_OK" not in log or "FORBIDDEN_OPCODE_EXECUTION" in log:
    raise SystemExit(f"Probe failed: exit {result.returncode}")
if hashlib.sha256(ROM.read_bytes()).hexdigest() != expected:
    raise SystemExit("ROM changed during diagnostic")
marker = next(line for line in log.splitlines() if line.startswith("NATIVE_PROBE_OK"))
report = dict(re.findall(r"(\w+)=([^ ]+)", marker))
for key in ("frames", "gameplay_frames", "moving_frames", "projectile_frames", "audible_frames", "final_state", "cpu_opcodes", "spc_opcodes"):
    report[key] = int(report[key])
report["campaign_verified"] = False
report.update(reference_revision="578f90b3cc49557bb70060ad033bb90b8cf8ac50", rom_sha256=expected, godot_integration=False, scope="compiled C reference boot, intro, first Ceres room, movement, shooting and native audio; no complete campaign verification")
(ROOT / "docs/qa/native_probe.json").write_text(json.dumps(report, indent=2) + "\n")
