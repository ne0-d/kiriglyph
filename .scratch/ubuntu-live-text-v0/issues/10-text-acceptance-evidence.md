# 10: Publish the Text milestone acceptance evidence

**What to build:** Maintainers can judge whether the text half of the overlay
should advance because its speed, resource use, privacy, text quality, and
Wayland behaviour are measured and reproducible.

**Blocked by:** 09: Keyboard focus and screen-reader basics for the overlay;
21: Remove the manual image workflow

**Status:** ready-for-human: run the manual checklist

- [ ] Shortcut-to-selectable-text latency is measured on a release build, split
  into silent capture, crop, OCR, and first paint, for one display and for the
  two-display setup, on documented hardware. Records cold and warm worker.
- [ ] Idle and peak memory of the resident app and worker, and stability over
  50 repeated activations (no growth in processes, files, or memory).
- [ ] Privacy tests verify that logs, temporary files, crash output, and
  settings contain no captured pixels or recognized text, that Pictures is
  untouched after a capture, and that `$XDG_RUNTIME_DIR` holds no session files
  after dismissal, quit, or a crash-and-restart.
- [x] A small pinned non-sensitive corpus records line recognition, character
  geometry and reading-order failures, and paragraph-grouping mistakes, with
  representative screenshots, so known limitations are documented.
- [ ] Manual Ubuntu 26.04 GNOME 50 Wayland results cover: text selection,
  circle, paused video, multiple displays, 100% and 125% scaling (already
  passed for the overlay), a revoked grant, and the first-run permission flow.
- [ ] Keyboard and Orca findings are listed with their known limitations
  rather than unsupported claims.
- [x] The report recommends whether to keep Flutter and Python, change the OCR
  adapter, run the production OCR bake-off, or reopen native-service research.

## Acceptance kit

- Draft report: `.scratch/ubuntu-live-text-v0/acceptance/text-milestone-report.md`
- OCR corpus evidence: `.scratch/ubuntu-live-text-v0/evidence/ocr-corpus-results.md`
- Resource and privacy scripts: `scripts/acceptance/`
