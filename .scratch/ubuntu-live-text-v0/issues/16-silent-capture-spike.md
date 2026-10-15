# 16: Prove silent capture and active-display placement

**What to build:** A throwaway prototype that answers the open questions in
[ADR 0001](../../../docs/adr/0001-selection-overlay-silent-capture.md) before
the overlay is built.

**Type:** prototype

**Blocked by:** none

**Status:** resolved

- [x] With a real application ID and installed desktop file, the focused app
  triggers GNOME's access dialog once, and the grant is stored against that ID
  (not the empty ID).
- [x] After the grant, a capture from the hidden resident app succeeds without
  a dialog.
- [x] Measured capture latency (median of 10) and whether GNOME flashes the
  screen or plays a sound.
- [x] A fullscreen undecorated GTK window opens on the display under the
  pointer, for each display, and reports that display's geometry and scale.
- [ ] Cropping the spanning image to that display is pixel-exact at 100% and
  at one fractional scale (for example 125%), shown side by side. *100%
  verified pixel-identical on both displays; 125% skipped by user decision and
  carried into issue 18 acceptance.*
- [x] The returned file is deleted, and no other file in Pictures is touched.
- [x] Findings are appended to ADR 0001 and its open questions closed or
  re-scoped.

## Answer

Silent capture is viable: one-time grant under a registered app ID, median
520 ms capture, window lands on the pointer's display, and the 1:1 crop is
pixel-identical at 100%. GNOME always flashes and plays a shutter sound;
accepted. Registration must happen on a private D-Bus connection (or in the
helper) because GTK3 startup already uses the shared one. Prototype:
`spikes/silent-capture/`.
