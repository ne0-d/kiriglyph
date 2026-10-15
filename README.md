# Kiriglyph

An experimental, local-first Ubuntu desktop application for selecting and copying
text from whatever is on your screen. Flutter provides the desktop UI; a long-lived
Python worker performs local OCR over versioned NDJSON.

## Name

**Kiriglyph** combines *kiri* (Japanese for “cut”) and *glyph* (a character):
the app cuts characters and subjects out of whatever is on your screen.

## Current V0

- Press a GNOME shortcut to freeze the display under the pointer and select text
  on the frozen pixels (drag, double-click word, triple-click paragraph, circle
  gesture, or the keyboard: arrows, Ctrl+Shift+Up/Down for paragraphs, Ctrl+C;
  see `app/README.md`).
- Drag across text to select it, or click/draw around an object in the same
  overlay. Shift-click adds foreground, Alt/right-click adds background,
  Ctrl-click forces object selection over text, Ctrl+Z undoes object prompts,
  and Backspace/Delete clears the object. Once a subject is selected, it pops
  out against a darkened frozen screen with Copy image, Save PNG, and Remove
  selection next to it. Save PNG writes directly to Pictures; Ctrl+Shift+S
  opens Save as...
- If no text is found, the frozen overlay stays open and points you to Subject
  mode instead of closing.
- Run OCR locally with RapidOCR and ONNX Runtime CPU inside the selection overlay.
- Copy selected text, all recognized lines, or the selected subject image to the
  clipboard.
- Use the normal window only for setup: one-time instant capture permission,
  shortcut instructions, and quit.

The OCR models are pinned and bundled by the Python dependency setup. Recognition
does not use an LLM, upload image data, or download models while processing a
capture.

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

Wayland with the GNOME screenshot portal is required for silent shortcut capture.

## Verification

```bash
cd app
../.tools/flutter/bin/dart format --output=none --set-exit-if-changed lib test
../.tools/flutter/bin/flutter analyze
../.tools/flutter/bin/flutter test

cd ../worker
../.tools/uv-bin/uv run --locked --project . pytest -q
```

Acceptance evidence scripts live in `scripts/acceptance/`; the desktop capture
and resource checks are user-run because they can flash the real screen.
