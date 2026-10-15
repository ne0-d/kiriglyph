#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER="$ROOT/.tools/flutter/bin/flutter"
WORKER_PYTHON="$ROOT/worker/.venv/bin/python"

if [[ ! -x "$FLUTTER" || ! -x "$WORKER_PYTHON" ]]; then
  printf 'Development dependencies are missing. Run ./scripts/bootstrap.sh first.\n' >&2
  exit 1
fi

if ! command -v clang++ >/dev/null 2>&1 ||
  ! command -v cmake >/dev/null 2>&1 ||
  ! command -v ninja >/dev/null 2>&1 ||
  ! pkg-config --exists gtk+-3.0 2>/dev/null; then
  printf 'Flutter Linux build prerequisites are missing.\n' >&2
  printf 'Install them with:\n' >&2
  printf '  sudo apt-get update && sudo apt-get install -y clang pkg-config libgtk-3-dev libstdc++-12-dev\n' >&2
  exit 1
fi

export KIRIGLYPH_WORKER_ROOT="$ROOT/worker"
export KIRIGLYPH_WORKER_PYTHON="$WORKER_PYTHON"
# Run as a separate, non-resident instance even while the installed app is
# running; otherwise the launch would be forwarded to it and exit.
export KIRIGLYPH_DEV_INSTANCE=1

cd "$ROOT/app"
exec "$FLUTTER" run -d linux "$@"
