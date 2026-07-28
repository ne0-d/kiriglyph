# 10: Publish the Text milestone acceptance evidence

**What to build:** Maintainers can judge whether the local character-selection
workflow should advance because its OCR quality, geometry, responsiveness,
resource use, privacy, accessibility, and Wayland behavior are reproducible.

**Blocked by:** 06: Drag across exact text ranges; 07: Capture visible content
through GNOME; 08: Launch capture from a GNOME shortcut; 09: Make the Text flow
keyboard and accessibility operable.

**Status:** blocked

- [ ] A pinned non-sensitive corpus records line and character recognition,
  geometry failures, reading-order failures, and representative screenshots.
- [ ] Cold worker start, model load, first OCR, warm OCR, and complete
  shortcut-to-selection latency are measured on documented hardware.
- [ ] Idle and peak memory, development dependency size, and repeated-request
  stability are recorded.
- [ ] Tests verify that logs, temporary files, crash output, and retained
  settings contain no captured pixels or recognized text.
- [ ] Ubuntu 24.04 GNOME Wayland results cover portal capture, shortcut
  activation, cancellation, multiple monitors, fractional scaling, and paused
  video.
- [ ] Keyboard and assistive-technology findings include known limitations
  rather than unsupported claims.
- [ ] The report recommends whether to retain Flutter/Python, change the OCR
  adapter, run the production bake-off, or reopen native-service architecture
  research.
