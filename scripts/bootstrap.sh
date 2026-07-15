#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="$ROOT/.tools"
FLUTTER="$TOOLS/flutter/bin/flutter"
UV="$TOOLS/uv-bin/uv"

mkdir -p "$TOOLS"

if [[ ! -x "$FLUTTER" ]]; then
  git clone --depth 1 --branch 3.47.7 \
    https://github.com/flutter/flutter.git "$TOOLS/flutter"
fi

if [[ ! -x "$UV" ]]; then
  curl -LsSf https://astral.sh/uv/0.13.0/install.sh |
    env UV_INSTALL_DIR="$TOOLS/uv-bin" sh
fi

"$FLUTTER" config --enable-linux-desktop
(cd "$ROOT/app" && "$FLUTTER" pub get)
(cd "$ROOT/worker" && "$UV" sync --locked --group dev)

missing=()
for command in clang++ pkg-config cmake ninja; do
  command -v "$command" >/dev/null 2>&1 || missing+=("$command")
done

if ! pkg-config --exists gtk+-3.0 2>/dev/null; then
  missing+=("libgtk-3-dev")
fi

if ((${#missing[@]})); then
  printf '\nFlutter Linux build prerequisites are missing: %s\n' "${missing[*]}"
  printf 'Install them with:\n'
  printf '  sudo apt-get update && sudo apt-get install -y clang pkg-config libgtk-3-dev libstdc++-12-dev\n'
else
  printf '\nDevelopment dependencies are ready.\n'
fi
