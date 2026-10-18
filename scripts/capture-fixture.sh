#!/usr/bin/env bash
# Save one RAW screen capture as a local test fixture (no overlay pixels).
# Usage: scripts/capture-fixture.sh <name>
# Open the page you want to test first; the capture happens after a 3 s delay.
# The image goes to worker/benchmarks/segmentation/fixtures/real/<name>.png
# (git-ignored) with owner-only permissions. Needs the one-time screenshot grant
# for dev.kiriglyph.Kiriglyph (the setup window's "Enable instant capture").
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="${1:?usage: scripts/capture-fixture.sh <name>}"
case "$name" in
*[!A-Za-z0-9._-]* | "")
  echo "name may contain only letters, digits, dot, dash, underscore" >&2
  exit 2
  ;;
esac
dest_dir="$ROOT/worker/benchmarks/segmentation/fixtures/real"
mkdir -p "$dest_dir"
dest="$dest_dir/$name.png"

echo "Capturing in 3 seconds. Make sure Kiriglyph's overlay is NOT open."
sleep 3
result="$(cd "$ROOT/worker" && PYTHONPATH=src .venv/bin/python -m worker.portal_capture \
  --silent --app-id dev.kiriglyph.Kiriglyph 2>/dev/null)"
path="$(printf '%s' "$result" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("path","") if d.get("outcome")=="captured" else "")')"
if [ -z "$path" ] || [ ! -f "$path" ]; then
  echo "Capture failed: $result" >&2
  exit 1
fi
install -m 0600 "$path" "$dest"
rm -f -- "$path"
echo "Saved $dest"
echo "Add a prompt entry for it in worker/benchmarks/segmentation/fixtures/real/manifest.json."
