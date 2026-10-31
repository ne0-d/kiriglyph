#!/bin/bash
# Runs INSIDE the clean Ubuntu 26.04 rootfs. Phase A: install and static checks.
set -uo pipefail
DEB=${1:-/tmp/kiriglyph_amd64.deb}
fail=0
ok()   { printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fail=1; }

echo "== installing $DEB with apt (pulls the declared dependencies)"
apt-get install -y "$DEB" >/tmp/apt-install.log 2>&1 && ok "apt-get install exit 0" || { bad "apt-get install failed"; tail -25 /tmp/apt-install.log; }

dpkg -s kiriglyph >/tmp/dpkg-status.txt 2>&1 && ok "dpkg reports kiriglyph installed ($(awk '/^Version:/{print $2}' /tmp/dpkg-status.txt))" || bad "dpkg -s kiriglyph"
apt-get check >/dev/null 2>&1 && ok "apt-get check: dependency tree consistent" || bad "apt-get check"

echo "== libraries the app loads at run time came with the package alone"
ldconfig -p | grep -q 'libGLESv2.so.2' && ok "libGLESv2 is present" || bad "libGLESv2 missing (Flutter aborts without it)"
ldconfig -p | grep -q 'libEGL.so.1' && ok "libEGL is present" || bad "libEGL missing"
gsettings list-schemas 2>/dev/null | grep -qx 'org.gnome.desktop.interface' && ok "GNOME desktop settings schemas are present" || bad "org.gnome.desktop.interface schema missing"

echo "== launcher"
kiriglyph --version && ok "kiriglyph --version" || bad "kiriglyph --version"
kiriglyph --help | head -3 && ok "kiriglyph --help" || bad "kiriglyph --help"
# The Ubuntu base image tells dpkg to skip man pages and docs, and dpkg -L then hides them too,
# so read the package file itself.
# (Capture the listing first: with pipefail, grep -q ending the pipe early would fail the check.)
listing=$(dpkg-deb -c "$DEB")
grep -q ' \./usr/share/man/man1/kiriglyph.1.gz$' <<<"$listing" && ok "package ships a man page" || bad "man page missing from the package"

echo "== every ELF file resolves all of its shared libraries"
scanned=0
missing=0
while IFS= read -r f; do
  scanned=$((scanned+1))
  out=$(ldd "$f" 2>&1 | grep 'not found' || true)
  if [ -n "$out" ]; then echo "  $f"; echo "$out" | sed 's/^/    /'; missing=$((missing+1)); fi
done < <(find /usr/lib/kiriglyph -type f \( -name '*.so' -o -name '*.so.*' -o -perm -u+x \) -exec sh -c 'for f; do head -c4 "$f" 2>/dev/null | grep -q ELF && echo "$f"; done' sh {} +)
# A check that scanned nothing must not pass.
[ "$scanned" -ge 50 ] || bad "only $scanned ELF files were scanned; the scan did not run properly"
[ "$missing" -eq 0 ] && ok "no unresolved shared libraries (scanned $scanned ELF files)" || bad "$missing ELF files have unresolved libraries"

echo "== no build-machine paths in Kiriglyph's own native libraries"
# libapp.so is Flutter's compiled Dart snapshot; like every Flutter app it records the source
# paths it was built from, so it is excluded here and noted in docs/packaging.md.
leak=$(grep -l --binary-files=text "image-segment-ai" /usr/lib/kiriglyph/kiriglyph /usr/lib/kiriglyph/lib/*.so 2>/dev/null | grep -v '/libapp.so$' || true)
[ -z "$leak" ] && ok "no repository path in the runner or plugin libraries" || bad "repository path found in: $leak"
runpaths=$(for f in /usr/lib/kiriglyph/kiriglyph /usr/lib/kiriglyph/lib/*.so; do readelf -d "$f" 2>/dev/null | grep -E 'RUNPATH|RPATH' | grep -v -E '\$ORIGIN' || true; done)
[ -z "$runpaths" ] && ok "every RUNPATH in the app is relative to the install (\$ORIGIN)" || { bad "unexpected RUNPATH:"; echo "$runpaths"; }

echo "== bundled models verify against their pinned hashes"
export PYTHONPATH=/usr/lib/kiriglyph/worker/src KIRIGLYPH_MODELS_DIR=/usr/lib/kiriglyph/models
PY=/usr/lib/kiriglyph/worker-runtime/bin/python
# A normal user cannot write into /usr/lib, so Python never caches bytecode there. This test runs as
# root, so it must not either, or it would leave files the package does not own (the -B flag).
"$PY" -I -B -c 'import sys; sys.path.insert(0, "/usr/lib/kiriglyph/worker/src"); from worker.segmentation_models import verify_assets; verify_assets(); print("segmentation model hashes ok")' && ok "EfficientSAM-Ti hashes" || bad "model verification"

echo "== bundled OCR reads text offline from a generated image"
"$PY" -I -B - <<'PYEOF' && ok "RapidOCR recognised the text" || bad "OCR smoke test"
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from rapidocr import RapidOCR

img = Image.new("RGB", (900, 160), "white")
draw = ImageDraw.Draw(img)
draw.text((30, 40), "Kiriglyph beta works", fill="black", font=ImageFont.load_default(size=64))
engine = RapidOCR()
result = engine(np.array(img))
text = " ".join(result.txts or [])
print("recognised:", repr(text))
sys.exit(0 if "iriglyph" in text and "beta" in text else 1)
PYEOF

echo "== segmentation models load in the bundled runtime"
"$PY" -I -B - <<'PYEOF' && ok "ONNX Runtime opened both EfficientSAM-Ti models" || bad "ONNX session"
import glob
import onnxruntime as ort
files = sorted(glob.glob("/usr/lib/kiriglyph/models/efficientsam-ti/*.onnx"))
assert len(files) == 2, files
for f in files:
    s = ort.InferenceSession(f, providers=["CPUExecutionProvider"])
    print(f.rsplit("/", 1)[-1], "inputs:", [i.name for i in s.get_inputs()][:3])
PYEOF

exit $fail
