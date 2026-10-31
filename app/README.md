# Kiriglyph app

The Flutter UI and the GTK runner for [Kiriglyph](../README.md): a desktop tool that selects and copies text from anything on your screen, or lifts an object out as a transparent PNG, with one shortcut. This folder is what you build and run; see the [root README](../README.md) for what it is, how to install it, and how to use it.

## What is here

| Path | Purpose |
| --- | --- |
| `lib/app/` | Native command channel (`app_shell.dart`), lifecycle, app identity |
| `lib/overlay/` | Overlay session controller, display crop math |
| `lib/ui/overlay/`, `lib/ui/workspace/` | Overlay screen, toolbar, selection canvas, mask painting |
| `lib/selection/` | Pure selection logic (no widgets): rectangles, intent, outcomes, paragraphs |
| `lib/capture/`, `lib/worker/`, `lib/segmentation/` | Ports and adapters for the screenshot portal, the OCR worker, and the segmentation worker |
| `lib/a11y/`, `lib/theme/`, `lib/tray/`, `lib/background/` | Announcer and shortcut table, Yaru theme, top-bar tray icon, launch at login |
| `lib/settings/`, `lib/shortcut/`, `lib/ui/settings/` | Saved settings and folder chooser, the GNOME shortcut service (`gsettings`), and the preferences page |
| `linux/runner/my_application.cc` | GTK runner: single instance, window modes and header-bar menu, the overlay's locate and show steps, clipboard, save and folder dialogs |
| `test/` | Widget and unit tests; `test/support/overlay_fakes.dart` holds the fakes |

## How the window behaves

The normal window is a small preferences and first-run page: screen access, the GNOME shortcut (added automatically on first run, changeable there), the save folder, launch at login, and pause. Quit is in the header bar's main menu. Selection happens in the fullscreen overlay started by `kiriglyph --select`, not by opening image files in the window.

The overlay does not appear until it can show the frozen picture. Dart asks the runner to find the display under the pointer with a small transparent probe window (`locateDisplay`), crops and renders the frame, and only then asks the runner to go fullscreen on that display (`showOverlay`). GNOME paints black behind a fullscreen window until opaque content covers the monitor, so mapping it any earlier shows a black frame. The reasoning is in [ADR 0002](../docs/adr/0002-overlay-maps-once-on-a-located-display.md).

## Overlay controls

- **Text and objects share one overlay.** Drag across text to select characters, double-click a word, triple-click a paragraph, or draw a loop (Free draw tool) that the app classifies as text or an object. Click an object to lift it, <kbd>Shift</kbd>+click to add, <kbd>Alt</kbd>+click or right-click to leave a part out, and <kbd>Ctrl</kbd>+click or drag to force object selection over text.
- **Rectangle is the default tool.** Press <kbd>T</kbd> to cycle Rectangle, Two clicks, and Free draw. Chips offer Copy text, Lift object, Copy screenshot, and Save screenshot.
- **Copy and save.** <kbd>Ctrl</kbd>+<kbd>C</kbd> copies text, or the object as a transparent PNG. <kbd>Ctrl</kbd>+<kbd>S</kbd> saves straight to your save folder (Pictures by default) as `kiriglyph-YYYYMMDD-HHMMSS.png`. <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>S</kbd> opens Save as... for an object without hiding the overlay, and <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>F</kbd> saves the whole display.
- **Undo and clear.** <kbd>Ctrl</kbd>+<kbd>Z</kbd> undoes the last object point; <kbd>Backspace</kbd> or <kbd>Delete</kbd> removes the object. <kbd>O</kbd> shows a keyboard object cursor: move it with the arrow keys and press <kbd>Enter</kbd> to lift the object under it.
- **Everything has a key.** Press <kbd>?</kbd> or <kbd>F1</kbd> in the overlay for the full list; it is generated from `lib/a11y/keyboard_shortcuts.dart`.

## Develop

Run these from the repository root; the Flutter SDK is the repo-local one (`.tools/flutter`). Quote the path: it may contain spaces.

```bash
./scripts/run-dev.sh              # run the app from source
./scripts/check.sh quick test/selection_overlay_test.dart   # format, analyze, listed tests
./scripts/check.sh full --build   # everything, including the Linux debug build
```

Tool paths and gotchas: [docs/agents/dev-commands.md](../docs/agents/dev-commands.md).
