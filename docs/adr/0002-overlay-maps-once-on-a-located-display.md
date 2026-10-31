# 0002: The overlay maps once, on a display found beforehand

**Status:** accepted. Implemented in issue 27; confirmed on the owner's desktop.

Refines [ADR 0001](0001-selection-overlay-silent-capture.md): the overlay is
still a borderless fullscreen window on the display under the pointer, but the
order in which it is shown changed.

## Context

Issue 26 tried to open the overlay "instantly with no black flash" by mapping
the fullscreen window at opacity 0, learning its display, publishing the frozen
frame, then raising the opacity. On a real desktop (Ubuntu 26.04, GNOME Shell
50.1, Mutter 50.1, GTK 3.24, Wayland) a full-screen recording of the shortcut
still showed one completely black frame between GNOME's white capture flash and
the overlay.

## Evidence

- **Opacity does nothing on Wayland.** GDK's Wayland backend implements
  toplevel opacity as an empty function (`gdk_wayland_window_set_opacity`), and
  the GTK 3 documentation says toplevel opacity "depends on the windowing
  system". The reveal never hid anything.
- **A transparent fullscreen window cannot show the desktop on GNOME.** Mutter
  creates a black actor behind any Wayland window that has acked fullscreen,
  unless one opaque surface exactly covers the monitor
  (`maybe_configure_black_background()` in
  `src/compositor/meta-window-actor-wayland.c`, added in Mutter 43.1; see
  Mutter issue 2520). xdg-shell allows this: a fullscreen surface that does not
  cover its output gets a border fill, "e.g. solid black".
- **Hiding Flutter's view was not enough.** Keeping the view hidden left a
  transparent, fullscreen, non-opaque window, which Mutter still backed with
  black.
- **What does work:** Mutter does not show a Wayland window until it has
  committed a buffer. GDK freezes drawing until the first xdg configure
  arrives. `FlView`'s draw handler (`fl_compositor_render` with
  `wait_for_frame`) blocks until Flutter has presented a frame at the window's
  size. So a fullscreen window whose first draw already contains the frozen
  frame never shows black.
- **Placement:** Mutter places a window shown for the first time on the
  backend's current logical monitor (`meta_window_place`), which is the monitor
  with the pointer. GDK learns a surface's output only after the compositor
  shows it; until then it falls back to the monitor at the layout origin.

## Decision

Map the fullscreen window once, with the frozen frame already rendered, aimed
at a display chosen beforehand.

1. **Locate.** `locateDisplay` shows a 1x1, undecorated, transparent probe
   window that is not fullscreen, so Mutter paints no black behind it. It waits
   for the probe's first draw, then reports the monitor once GDK's answer has
   been stable for 150 ms, and destroys the probe.
2. **Freeze.** Dart decodes and crops the capture for that monitor, publishes
   the frame, and waits two rendered frames so Flutter's last presented frame
   is the frozen one.
3. **Show once.** `showOverlay(display)` calls
   `gtk_window_fullscreen_on_monitor` and presents. The call completes when the
   window is fullscreen at the monitor's size and two paint cycles have passed
   (with a timeout, so Dart never waits forever).

Decoding runs while the probe settles, so the locate step adds little to the
total time.

## Alternatives considered

- **Transparent fullscreen window, reveal later** (issue 26): black until the
  opaque frame arrives, as above.
- **Hide Flutter's view until reveal:** still a non-opaque fullscreen window.
- **A borderless window that is not fullscreen:** no black backdrop, but the top
  bar stays and Wayland gives the app no control over its position.
- **A GNOME Shell extension:** how GNOME's own screenshot tool avoids the
  problem, since it draws inside the compositor. Rejected for now: a second
  codebase (JavaScript) tied to Shell versions.
- **A fade-in:** cosmetic; it would hide the symptom, not remove it.

## Consequences

- The probe window may briefly take focus or trigger GNOME's "is ready" notice,
  because GTK 3 on Wayland ignores no-focus requests.
- Flutter must keep rendering while the window is hidden. The Linux embedder's
  vsync is a timer, not the window's frame clock, so it does.
- The failure screen shown when there is no screenshot (no frame to show) still
  sits on Mutter's black backdrop.
- The runner's native code cannot be unit-tested. Dart behaviour (order of
  locate, freeze, show; abandon on failure) is covered by tests with a fake
  shell. The fix is confirmed by recording the shortcut.

## Open questions

- Two displays with different sizes, and 125% scaling, have not been recorded
  since the change (issue 27 acceptance).
- If a future Mutter stops painting black behind non-opaque fullscreen
  windows, the probe could be dropped and the overlay could map transparent
  again. Re-check the Mutter source before assuming either behaviour.
