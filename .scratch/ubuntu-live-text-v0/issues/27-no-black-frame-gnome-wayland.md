# 27: No black frame when the overlay opens on GNOME Wayland

**What to build:** The selection overlay opens with the frozen screenshot as the
first thing the compositor ever shows, and never shows a black frame first.

**Blocked by:** nothing. Follows 26 (its "instant open, no black flash"
acceptance box was never met on a real desktop).

**Status:** implemented and confirmed by the owner on their desktop (no black
frame after the change). Two-display and 125% runs are not recorded yet.

## Evidence

- A screen recording of the installed app (Ubuntu 26.04.1, GNOME Shell 50.1,
  Mutter 50.1, GTK 3.24.52, Wayland) shows one fully black frame, then the
  overlay, right after GNOME's white capture flash.
- Mutter draws a black actor behind every Wayland window that has acked
  fullscreen unless a single opaque surface exactly covers the monitor
  (`maybe_configure_black_background()` in
  `src/compositor/meta-window-actor-wayland.c`, added in Mutter 43.1;
  Mutter issue 2520). xdg-shell also says a fullscreen surface that does not
  cover the output gets a border fill, "e.g. solid black".
- So a **transparent fullscreen window cannot show the desktop through it** on
  GNOME. Issue 26's design (map fullscreen and transparent to learn the
  display, reveal later) shows black from the fullscreen ack until the opaque
  frozen frame is on screen. GDK's Wayland backend also ignores toplevel
  opacity (`gdk_wayland_window_set_opacity` is an empty function), so the
  `gtk_widget_set_opacity` reveal did nothing.
- Mutter does not show a Wayland window until it commits a buffer, and GDK
  freezes drawing until the first xdg configure arrives. FlView's draw handler
  (`fl_compositor_render` with `wait_for_frame`) blocks until Flutter has
  rendered a frame at the window's size. So a fullscreen window whose first
  draw already contains the frozen frame never shows black.

## Design

The fullscreen window must be mapped **once**, with the frozen frame already
in Flutter's state, and aimed at a display chosen beforehand.

1. **Locate (no fullscreen).** New native call `locateDisplay`: map a small
   (1x1), undecorated, transparent, non-focusable probe `GtkWindow`. Mutter
   places a window shown for the first time on the monitor under the pointer
   (`meta_backend_get_current_logical_monitor` in `meta_window_place`). Poll
   `gdk_display_get_monitor_at_window` until the answer has been stable for
   `kPlacementSettleUs` (150 ms): GDK only learns the output after the
   compositor shows the surface, and until then falls back to the monitor at
   the layout origin. Reply with the same placement map as today
   (`target`, `monitors`), then destroy the probe.
2. **Freeze.** Dart decodes and crops as today, publishes the frame to the
   overlay state, and waits two rendered frames so Flutter's last presented
   frame is the frozen one.
3. **Show once.** New `showOverlay(display)`: `gtk_window_fullscreen_on_monitor`
   on that display, undecorated, then present. The first draw blocks until
   Flutter has a frame at the monitor's size, so the first buffer is the
   frozen frame. Complete the call after the window is mapped, fullscreen at
   the monitor's size, and `kRevealPaints` GTK paint cycles have passed (with
   the existing timeout so it never hangs).
4. Remove the Flutter-view hide/show and `revealOverlay` from the earlier
   attempt, and the `gtk_widget_set_opacity` calls. Keep the normal-window
   `presented`/`present` handshake from that attempt.

Failure without a frame (`_failWithoutFrame`) keeps its behaviour: locate,
then show the overlay with the message.

## Acceptance

- [x] `scripts/check.sh full --build` prints `CHECK PASSED`.
- [x] Tests cover: locate before show, show only after the frame is published,
      abandon when locate or show fails, the failure-message path, dismissal
      during locate, and a show that never completes.
- [ ] Manual (user-run, it flashes the real screen): no black frame on the
      shortcut, on one and two displays, at 100% and 125%; screen-record it.
      Done: the owner reports no black frame on their desktop after the
      change. Still open: two displays of different sizes, and 125% scaling.
- [x] Phase timings (`forward`, `portal`, `read`, `decode`, `map`, `crop`,
      `reveal`) still recorded; `map` ends when the display is located,
      `reveal` when the overlay is on screen. Not yet compared against numbers
      from a recorded run.

## Out of scope

Moving the overlay into a GNOME Shell extension; making the failure screen
(no frame) look better than a message on black.

## Outcome

Decision record: [ADR 0002](../../../docs/adr/0002-overlay-maps-once-on-a-located-display.md).

**How the cause was found.** The first two attempts targeted the wrong layer.
Issue 26's opacity gating was a no-op on Wayland. Hiding Flutter's view (the
first fix for this ticket) removed Flutter's own black fill and a stale frame
on the normal window, but the overlay still flashed black. A frame-by-frame read
of a screen recording of the shortcut showed one pure-black frame between
GNOME's white capture flash and the overlay; the app's own code could not
explain it. Research then found Mutter's black backdrop behind non-opaque
fullscreen windows (see Evidence), which no amount of transparency in the app
can avoid.

**What changed.**

- `app/linux/runner/my_application.cc`: new `locateDisplay` (probe window),
  `showOverlay(display)` maps once with `gtk_window_fullscreen_on_monitor`
  and completes after the window is fullscreen at the display's size and two
  paint cycles; `revealOverlay`, the Flutter-view hide/show, and every
  `gtk_widget_set_opacity` call are gone. The normal-window handshake
  (`presented` then `present`, with an 800 ms fallback) from the first fix stays.
- `app/lib/app/app_shell.dart`: `locateDisplay()` and `showOverlay(int)`;
  `showOverlay` waits two rendered frames first; `present()` does the same.
- `app/lib/overlay/selection_overlay.dart`: order is locate, decode and crop,
  publish the frame, show, then OCR. The content timer now covers the show step.
- Tests: `FakeShell` records `locate` and `show` and can fail or hold either;
  six tests added or rewritten in `selection_overlay_test.dart`.

**Deviations from the ticket text.**

- The probe waits for its own first draw before the 150 ms settle starts. On
  Wayland, GTK reports a window as mapped before the compositor has configured
  it, so without this the settle could finish too early and pick the wrong
  display.
- After a show failure the frame is not disposed a second time: dismissing
  already disposes it, and a second dispose fails an assertion in debug builds.

**Risks that remain.**

- The probe may briefly take focus, or GNOME may show an "is ready" notice.
- The failure screen shown when there is no screenshot still sits on the black
  backdrop (out of scope).
- If Flutter stopped rendering while the window is hidden, each of the two
  frame waits would fall back to its 500 ms timeout; the overlay would open
  slower but not black.
- `display_layout.dart` has a comment that still names `showOverlay` for the
  locate reply.

## Comments

- Evidence for the cause: the Mutter source (`gnome-50` branch), Mutter issue
  2520, the xdg-shell `set_fullscreen` description, and the GDK Wayland source.
