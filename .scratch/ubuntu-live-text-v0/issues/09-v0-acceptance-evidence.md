# 09: Publish V0 acceptance evidence

**What to build:** Maintainers can judge whether the Flutter and Python prototype should advance because its OCR quality, responsiveness, resource use, privacy behavior, accessibility, and Wayland workflow are recorded with reproducible evidence.

**Blocked by:** 05: Validate and enable word selection; 06: Capture visible content through GNOME; 07: Launch capture from a GNOME shortcut; 08: Make the complete flow keyboard and accessibility operable.

**Status:** ready-for-agent

- [ ] A pinned non-sensitive corpus records line and word recognition, geometry failures, reading-order failures, and representative screenshots.
- [ ] Cold worker start, model load, first OCR, warm OCR, and end-to-end interaction latency are measured on documented hardware.
- [ ] Idle and peak memory, installed development dependency size, and repeated-request stability are recorded.
- [ ] Tests verify that logs, temporary files, crash output, and retained settings contain no captured pixels or recognized text.
- [ ] Ubuntu 24.04 GNOME Wayland results cover portal capture, shortcut activation, cancellation, multi-monitor behavior, fractional scaling, and paused video.
- [ ] Keyboard and assistive-technology findings are recorded, including known limitations rather than unsupported claims.
- [ ] The report recommends whether to retain Flutter/Python, change an adapter, run the production OCR bake-off, or reopen native-service architecture research.
