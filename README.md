# Ubuntu Live Text

An experimental, local-first Ubuntu desktop application for selecting text
from images. The first vertical slice uses Flutter for the desktop UI and a
long-lived Python worker over versioned NDJSON.

## Current V0

- Open a PNG, JPEG, GIF, BMP, or WebP image.
- Send its path to one local Python worker process.
- Render a deterministic mock OCR line over the image.
- Show the recognized text as selectable Flutter text.

The mock engine proves the complete app-to-worker path. Real local OCR is the
next ticket; this version does not use an LLM or send image data over a network.

## Ubuntu 24.04 setup

Install Flutter's Linux build prerequisites:

```bash
sudo apt-get update
sudo apt-get install -y clang pkg-config libgtk-3-dev libstdc++-12-dev
```

Bootstrap the pinned Flutter and Python tools:

```bash
./scripts/bootstrap.sh
```

Run the desktop application:

```bash
./scripts/run-dev.sh
```

The existing-image workflow works on both X11 and Wayland. No logout or session
switch is needed for V0. Wayland becomes important when system screenshot and
screen-capture support is added through XDG Desktop Portal.

## Verification

```bash
cd app
../.tools/flutter/bin/dart format --output=none --set-exit-if-changed lib test
../.tools/flutter/bin/flutter analyze
../.tools/flutter/bin/flutter test

cd ../worker
../.tools/uv-bin/uv run --locked --project . pytest -q
```

Shared protocol contracts are under `contracts/v1/`. The implementation plan
and ordered tickets are under `.scratch/ubuntu-live-text-v0/`.
