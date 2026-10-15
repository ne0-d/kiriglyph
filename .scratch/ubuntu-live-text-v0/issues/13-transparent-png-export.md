# 13: Export a selected subject as transparent PNG

**What to build:** From the overlay, a user can turn the active subject mask
into a background-removed RGBA image, copy it as an image, or save it as a
transparent PNG without retaining private content.

**Blocked by:** 12: Select a subject in the overlay by click or drawn region.

**Status:** implemented — automated export, cleanup, accessibility, and native
build checks are covered; real Wayland clipboard paste targets, the real GTK
file chooser from the overlay, and multi-display chooser behavior remain manual
verification items for 14.

- [x] Mask application preserves source color while deriving a correct alpha
  channel and useful cropped bounds.
- [x] Edge handling avoids obvious halos without inventing content outside the
  validated mask.
- [x] The object action chip offers Copy image and Save PNG, with keyboard
  shortcuts.
- [x] Copy image publishes a standards-compatible PNG or image clipboard payload
  on Ubuntu Wayland, still available to paste after the overlay is dismissed.
- [x] Save PNG writes directly to Pictures with a unique timestamped name and
  valid PNG output. Save as... keeps the overlay visible while the chooser is
  open.
- [x] Cancellation, clipboard failure, encoder failure, invalid masks, and
  unwritable destinations are distinct recoverable outcomes.
- [x] Temporary buffers and files are released when export completes, fails, is
  cancelled, or the overlay is dismissed.
- [x] Tests verify dimensions, crop bounds, RGBA pixels, alpha semantics,
  clipboard payloads, PNG decoding, cleanup, and privacy-safe diagnostics.

## Implementation notes

- Dart composes the cutout from raw RGBA buffers in `SubjectCutoutComposer`.
  The crop uses the mask stats bounds with default padding 0, clamped to the
  source image when a caller opts into padding.
- Halo handling is conservative: only fully opaque mask pixels stay visible.
  Partially-transparent fringe pixels are made transparent, and their RGB is
  filled from the nearest fully-opaque interior pixel so consumers that sample
  edge colour do not reveal background-coloured halos. The mask is never grown.
- Copy image calls the native `kiriglyph/app` method channel with PNG bytes.
  GTK owns an `image/png` clipboard target from the resident process, so hiding
  or dismissing the overlay does not intentionally clear the selection.
- Save PNG writes through a temp file in Pictures, then renames atomically.
  Save as... opens a `GtkFileChooserNative` with the overlay still visible and
  asks before overwrite. Success keeps the overlay open.
- While the chooser is open, Dart marks export in progress and native focus-loss
  dismissal is suppressed. Focus loss during that window does not end the
  capture session.

Automated evidence:

- `flutter test test/subject_cutout_test.dart test/subject_export_controller_test.dart`
  covers crop bounds, padding, RGBA/alpha semantics, fringe decontamination,
  invalid masks, PNG decode, clipboard and save outcomes, temp cleanup, and
  privacy-safe diagnostics.
- `flutter test test/selection_overlay_test.dart test/subject_overlay_screen_test.dart`
  covers chooser-open focus guard, direct-save behavior, object action chip
  buttons, Ctrl+C/Ctrl+S shortcuts, Tab order, and status feedback.
- `flutter build linux --debug` compiles the native clipboard and chooser code.

Manual verification pending in 14:

- Copy image from the object action chip, dismiss the overlay, then paste into Firefox,
  Chromium, GIMP, LibreOffice, and Telegram on GNOME Wayland.
- Save PNG from the fullscreen overlay, confirm it saves directly to Pictures
  and leaves the selection open. Confirm Save as... appears above the visible
  overlay and cancel keeps the same frozen selection.
- Confirm overwrite confirmation appears for an existing PNG and declining it
  leaves the original file untouched.
- Repeat Copy image and Save PNG on one and two displays, including the display
  that did not launch the setup window.

## Fixes after desktop testing

- Subject export actions moved from the main toolbar to the object action chip
  next to the popped-out selection. The keyboard shortcuts remain Ctrl+C for
  Copy image, Ctrl+S for Save PNG, and Backspace/Delete for removing the
  current subject.
- The save dialog suggestion is now timestamped as
  `kiriglyph-YYYYMMDD-HHMMSS.png`; the GTK overwrite confirmation remains the
  guard when a chosen destination already exists.
- The export path and overlay painter share the same mask coverage rule: use
  alpha when it is meaningful, otherwise use grayscale luminance for legacy
  opaque masks.
