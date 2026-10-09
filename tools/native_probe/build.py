#!/usr/bin/env python3
"""Compile the pinned C reference without SDL; block CPU/SPC opcode execution.

This is a fidelity research probe, not the Godot game or a complete-campaign test.
Generated sources live in build/ and never alter the reference or local ROM.
"""
from pathlib import Path
import subprocess
import re

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "tools/reference_native/src"
OUT = ROOT / "tools/native_probe/build"
OUT.mkdir(exist_ok=True)
expected = "578f90b3cc49557bb70060ad033bb90b8cf8ac50"
revision = subprocess.check_output(["git", "-C", str(SRC.parent), "rev-parse", "HEAD"], text=True).strip()
if revision != expected:
    raise SystemExit(f"Unexpected reference revision: {revision}")

sources = sorted(SRC.glob("sm_*.c")) + [SRC / n for n in ["spc_player.c", "util.c", "tracing.c"]]
sources += sorted((SRC / "snes").glob("*.c"))
objects = []
for source in sources:
    generated = source
    if source.name in ("cpu.c", "spc.c"):
        name = source.stem + "_runOpcode"
        text = source.read_text()
        match = re.search(r"int " + name + r"\([^)]*\)\s*\{", text)
        if not match:
            raise SystemExit(f"Missing expected opcode entry: {name}")
        start, depth, end = match.end(), 1, match.end()
        while depth:
            depth += (text[end] == "{") - (text[end] == "}")
            end += 1
        text = text[:start] + '\n  fprintf(stderr, "FORBIDDEN_OPCODE_EXECUTION: ' + name + '\\n");\n  abort();\n}' + text[end:]
        generated = OUT / source.name
        generated.write_text(text)
    obj = OUT / (source.parent.name + "_" + source.stem + ".o")
    if not obj.exists() or obj.stat().st_mtime < max(source.stat().st_mtime, generated.stat().st_mtime):
        subprocess.run(["clang", "-c", "-O2", "-fno-strict-aliasing", "-Wno-unknown-pragmas", "-Wno-unused-value", "-I", str(SRC), "-I", str(SRC / "snes"), str(generated), "-o", str(obj)], check=True)
    objects.append(obj)
subprocess.run(["clang", "-O2", "-I", str(SRC), str(Path(__file__).with_name("probe.c")), *map(str, objects), "-lm", "-Wl,-dead_strip", "-o", str(OUT / "native_probe")], check=True)
print(OUT / "native_probe")
