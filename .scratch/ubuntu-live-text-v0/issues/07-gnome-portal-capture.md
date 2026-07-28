# 07: Capture visible content through GNOME

**What to build:** An Ubuntu Wayland user can invoke Capture Text, choose an
area, window, or screen in GNOME's trusted screenshot selector, and receive the
captured frame in the existing result workflow.

**Blocked by:** 03: Select and copy recognized lines; 04: Recover from worker
and OCR failures.

**Status:** ready-for-agent

- [ ] Capture uses the XDG Screenshot portal with an interactive request on
  Ubuntu 24.04 GNOME Wayland.
- [ ] A successful portal result is decoded and passed through the same local
  processing boundary used for opened images.
- [ ] User cancellation is a neutral outcome that leaves no stale result or
  error state.
- [ ] Portal unavailable, denied, failed, invalid URI, and unreadable capture
  are distinct recoverable outcomes.
- [ ] Temporary portal-provided files are cleaned up on success, failure,
  cancellation, and application exit where ownership permits.
- [ ] Manual Wayland tests cover area, window, screen, paused video, multiple
  monitors, and fractional scaling.
