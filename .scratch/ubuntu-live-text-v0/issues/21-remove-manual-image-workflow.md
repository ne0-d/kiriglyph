# 21: Remove the manual image workflow

**What to build:** The app has no "open an image" path. The overlay is the only
way to select content, and the normal window is a setup window only. This
removes code that the overlay made redundant.

**Blocked by:** none (18 and 20 are resolved)

**Status:** resolved

- [x] The setup window offers Enable instant capture, the GNOME shortcut steps
  with a copyable command, permission status, and Quit. Open image, New image,
  and the in-window result workspace (image canvas, recognized-text side
  panel, zoom bar) are removed.
- [x] The image-file picker port and its provider are removed for input. The
  `file_selector` dependency stays only if the Save PNG export (issue 13) still
  needs a save dialog; otherwise it is removed with its Linux plugin entry.
- [x] The shared selection canvas, paragraph grouping, smooth highlight,
  circle gesture, and the overlay keep working unchanged, including their
  tests. Code used only by the removed window (header actions, window result
  and error views) is deleted, not left dormant.
- [x] Capture session state no longer has an "open file" path; failures from
  the shortcut flow still reach the setup window with a clear message.
- [x] Tests that drove the app through Open image are rewritten to drive the
  overlay or the canvas directly; the test harness provides a simple way to
  show the overlay from a fixture image without a file picker.
- [x] Specs, README, and `docs` no longer describe opening an image manually.
- [x] Full Flutter and Python suites and the analyzer pass; the Linux build
  succeeds.
