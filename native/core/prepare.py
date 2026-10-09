from pathlib import Path
import sys
import subprocess

src, out = map(Path, sys.argv[1:])
revision = subprocess.check_output(["git", "-C", str(src.parent), "rev-parse", "HEAD"], text=True).strip()
if revision != "578f90b3cc49557bb70060ad033bb90b8cf8ac50":
    raise SystemExit("Unexpected gameplay reference revision")
out.mkdir(parents=True, exist_ok=True)
text = (src / "sm_rtl.c").read_text()
text = text.replace("void RtlReadSram(void)", "void ReferenceReadSram(void)")
text = text.replace("void RtlWriteSram(void)", "void ReferenceWriteSram(void)")
start = text.index("bool Unreachable(void) {")
end = text.index("\n}", start) + 2
text = text[:start] + 'bool Unreachable(void) { Die("Unsupported routine in the native reference"); return false; }' + text[end:]
target = out / "sm_rtl.c"
if not target.exists() or target.read_text() != text:
    target.write_text(text)
