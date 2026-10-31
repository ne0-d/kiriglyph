# 18: Selection overlay on the active display

**What to build:** Pressing the shortcut freezes the display under the pointer
in place and makes its text selectable, without visibly opening an app.

**Blocked by:** 15: Smooth text selection highlight; 17: Resident app and
shortcut activation

**Status:** resolved (manual acceptance passed on one and two displays, at 100% and 125%)

- [x] The app captures silently while hidden, crops the active display, and
  shows it in a borderless fullscreen window at exact physical size, so the
  desktop looks unchanged.
- [x] A short edge glow signals selection mode; a subtle scanning animation
  runs until OCR results are selectable. Both respect reduced-motion settings.
- [x] Drag, double-click, triple-click, Ctrl+C, and Ctrl+A work as in the
  workspace. A small floating Yaru toolbar offers Copy, Copy all, and Close.
- [x] Escape, Close, or focusing another display dismisses the overlay and
  discards the capture and OCR results.
- [x] Missing permission opens the secondary window at "Enable instant
  capture"; portal, OCR, and no-text failures show brief in-overlay messages.
- [x] Manual acceptance with one display and two displays, at 100% and one
  fractional scale. Not run: the boxes above are implemented and covered by
  automated tests, but nothing was shown on a real desktop yet.

## Implementation notes

The overlay is a mode of the existing window. On `select`, Dart
(`overlay/selection_overlay.dart`) calls `prepareCapture`, which hides a
visible window and replies after 300 ms so GNOME's close animation is not
captured. Dart then takes the silent capture, reads the returned file into
memory and deletes it. `showOverlay` hides the header bar, makes the window
undecorated and fullscreen with a transparent GTK background and FlView
background, and maps it. Before that, Flutter renders the overlay route,
which paints nothing. Mutter places the window on the pointer's display, and
the desktop shows through until the frozen frame is painted, so no empty
window flashes.

The monitor cannot be known before mapping. GDK learns it only after the
surface enters an output, and before that guesses from position 0,0. The
runner polls until the window is fullscreen, its size equals the monitor GDK
reports, and that has held for 150 ms. It then replies with every monitor's
logical geometry and GDK scale and the target index. It gives up after
2.5 s.

Cropping runs in Dart with `dart:ui`, in `overlay/display_layout.dart` and
`overlay/overlay_frame.dart`. This is the simplest private option: no worker
protocol change, the spanning image never returns to disk, and the GPU crop
is shown at once. Crop math uses only GDK's logical layout and the image
size: image scale = image px / logical stage size, and the target rect's
edges are multiplied by it and rounded. A display below the capture scale is
returned to its own density (logical size times its integer GDK scale).
Rotated displays need nothing extra, because logical geometry is
post-transform. A capture that does not fit the layout is rejected with a
message. Only the crop is PNG-encoded into the private 0600 store and sent to
OCR.

The UI is `ui/overlay/`. `CaptureCanvas.fullBleed` reuses the workspace
selection with no padding, zoom, image, background or panel, and leaves
Escape to the overlay. The frame is drawn with `FilterQuality.none` when
frame pixels equal buffer pixels. The selection follows the overlay's OCR
result while it is open.

Dismissal (Escape, Close, Alt+F4, or `overlayFocusLost`) hides the window,
then restores decorations, the header bar and the saved size. Dart then drops
the frame and text and deletes the private crop. If OCR is still running, the
worker is restarted. `overlayFocusLost` is sent after a 250 ms debounce, and
only once the overlay had been focused. Missing permission opens the normal
window with an onboarding notice. Capture, decode, layout, OCR and no-text
failures show a toolbar message and close after 3.5 s. If no frame is shown
within 5 s, or placement fails, the overlay closes and the normal window
reports it. Repeated `select` while active is ignored.

The dev instance (`run-dev.sh`) is non-unique, so `kiriglyph --select` does
not reach it. `flutter run --dart-entrypoint-args=--select` tries one
selection per launch. After dismissal the dev window stays hidden.

Risks not verified without a GUI:

- Whether FlView/GTK really composite transparently on Mutter. If not, a
  black frame shows for about 0.3 s before the frozen frame.
- Whether the window gets keyboard focus when activated from the shortcut.
  If not, Escape needs a click first.
- Whether clicking the bare desktop on another display counts as a focus
  loss.
- Fractional scaling. GTK3 renders at an integer scale, so at 125% the frame
  is drawn into a 2× buffer and the compositor scales it down: expect slight
  softness, not a pixel match. GDK3 must report xdg-output logical geometry
  for the crop to be right.

## Manual acceptance steps

1. `./scripts/install-desktop.sh`, then open Kiriglyph and choose "Enable
   instant capture" once. Bind `~/.local/bin/kiriglyph --select` to a custom
   shortcut.
2. **One display, 100%:** open a text-heavy page and press the shortcut. GNOME
   flashes, a short edge glow appears, and the screen looks unchanged (no
   window, title bar or shift). A light sweep runs, then the toolbar reads
   "Drag across text to select it". Drag, double-click, triple-click,
   Ctrl+A, Ctrl+C, Copy and Copy all. Paste to check the text. Escape closes
   it. Press again, then use Close. Press again, then Alt+Tab: the overlay
   closes.
3. **Two displays, 100%:** put the pointer on each display in turn and press
   the shortcut. Only that display freezes, the other stays live, and
   clicking a window on the other display closes the overlay.
4. **125% on one display** (Settings → Displays, fractional scaling): repeat
   steps 2 and 3. The frame should line up with no offset; slight softness is
   expected. Check that the selection highlight sits on the text.
5. **Reduced motion** (Settings → Accessibility → Reduce Animation): no glow
   or sweep.
6. **Failures:** revoke the grant (Settings → Apps → Kiriglyph → Screenshots)
   and press the shortcut. The normal window opens at onboarding with a
   notice. On a screen with no text, "No text was found on this display."
   shows and the overlay closes by itself.
7. After each dismissal, `ls $XDG_RUNTIME_DIR/kiriglyph-*` shows no
   `screen-capture-*.png`, and `~/Pictures` has no new `Screenshot*.png`.

## Comments

- The "Risks not verified" item about a black frame before the frozen frame turned out to be real on GNOME Wayland. Cause and fix: [issue 27](27-no-black-frame-gnome-wayland.md) and [ADR 0002](../../../docs/adr/0002-overlay-maps-once-on-a-located-display.md).
