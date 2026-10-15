# 07: Capture visible content through GNOME

**What to build:** An Ubuntu Wayland user can invoke Capture Text, choose an
area, window, or screen in GNOME's trusted screenshot selector, and receive the
captured frame in the existing result workflow.

**Blocked by:** 03: Select and copy recognized lines; 04: Recover from worker
and OCR failures.

**Status:** superseded by 18; the portal helper is reused with
`interactive=false` (see ADR 0001). The interactive picker button is removed in
20, so its manual acceptance is not pursued.

- [x] Capture uses the XDG Screenshot portal with an interactive request on
  GNOME Wayland (verified portal version 2 on Ubuntu 26.04 / GNOME 50).
- [x] A successful portal result is decoded and passed through the same local
  processing boundary used for opened images.
- [x] User cancellation is a neutral outcome that leaves no stale result or
  error state.
- [x] Portal unavailable, denied, failed, invalid URI, and unreadable capture
  are distinct recoverable outcomes.
- [x] File ownership: GNOME owns and keeps the saved screenshot (accepted V0
  side effect: Pictures/Screenshots, clipboard, recent files, notification).
  The app creates no temporary capture files and never deletes GNOME's file.
- [ ] Manual Wayland tests cover area, window, screen, paused video, multiple
  monitors, fractional scaling, Escape, and GNOME's side effects.

**Implementation notes:** A one-shot Python `dbus-fast` helper
(`worker.portal_capture`) subscribes to `Request::Response` before calling
`Screenshot` with `interactive=true` and prints one JSON outcome. Flutter's
`ScreenCapturePort` runs it per capture; `CaptureSessionController.captureScreen`
routes a captured path into the existing OCR flow. Verified: 126 Flutter tests,
76 Python tests, analyzer clean, `git diff --check` clean. The Linux build is
blocked locally until `libgtk-3-dev` is reinstalled after the OS upgrade.
