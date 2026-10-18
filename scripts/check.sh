#!/usr/bin/env bash
# One command that decides "done". Usage:
#   scripts/check.sh quick [app/test/foo_test.dart ...]   format + analyze + the listed tests
#   scripts/check.sh full  [--build]                      format + analyze + full app tests + worker tests
# Output is compact: one line per step, failing test names on error.
# Exit code is non-zero when any step fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER="$ROOT/.tools/flutter/bin/flutter"
DART="$ROOT/.tools/flutter/bin/dart"
mode="${1:-quick}"
shift || true
failed=0

step() { # step <label> <command...>; keeps the tail of the output on failure
  local label="$1"
  shift
  local out
  if out="$("$@" 2>&1)"; then
    printf 'ok    %s\n' "$label"
  else
    failed=1
    printf 'FAIL  %s\n' "$label"
    printf '%s\n' "$out" | grep -E "^\s*(/|lib/|test/).*(\[E\]|:[0-9]+:)|Failing tests|error •|FAILED|Error:|[0-9]+ (failed|errors?)" | head -25
    printf '%s\n' "$out" | tail -6
  fi
}

in_app() { (cd "$ROOT/app" && "$@"); }
in_worker() {
  (cd "$ROOT/worker" && KIRIGLYPH_MODELS_DIR=".models/segmentation" PYTHONPATH=src \
    .venv/bin/python -m pytest -q "$@")
}

step "format (run 'dart format lib test' in app/ to fix)" in_app "$DART" format --output=none --set-exit-if-changed lib test
step "analyze" in_app "$FLUTTER" analyze

case "$mode" in
quick)
  if [ "$#" -gt 0 ]; then
    step "tests: $*" in_app "$FLUTTER" test "$@"
  fi
  ;;
full)
  step "app tests (full)" in_app "$FLUTTER" test
  step "worker tests (full)" in_worker
  if [ "${1:-}" = "--build" ]; then
    step "debug build" in_app "$FLUTTER" build linux --debug
  fi
  ;;
*)
  echo "usage: scripts/check.sh quick [test files...] | full [--build]" >&2
  exit 2
  ;;
esac

if [ "$failed" -eq 0 ]; then
  echo "CHECK PASSED ($mode)"
else
  echo "CHECK FAILED ($mode)"
fi
exit "$failed"
