# 08: Launch capture from a GNOME shortcut

**What to build:** An Ubuntu 24.04 user can configure a GNOME custom shortcut
that activates Capture Text without manually opening the application first,
while repeated activation remains bounded to one active capture session.

**Blocked by:** 07: Capture visible content through GNOME.

**Status:** blocked

- [ ] The application exposes a stable capture-mode launch command suitable
  for GNOME Custom Shortcuts.
- [ ] Onboarding shows accurate, concise setup steps and lets the user copy the
  command.
- [ ] Shortcut activation presents the portal flow with valid foreground focus
  on Ubuntu 24.04 GNOME Wayland.
- [ ] Repeated activation does not create overlapping portal requests, workers,
  or result sessions.
- [ ] Existing-app and cold-start activation enter the same capture workflow.
- [ ] The application does not silently modify GNOME settings or install a
  Shell extension.
