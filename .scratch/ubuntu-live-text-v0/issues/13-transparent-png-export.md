# 13: Export a selected subject as transparent PNG

**What to build:** A user can turn the active subject mask into a
background-removed RGBA image, copy it as an image, or save it as a transparent
PNG without retaining private content.

**Blocked by:** 12: Select a subject by click or drawn region.

**Status:** blocked

- [ ] Mask application preserves source color while deriving a correct alpha
  channel and useful cropped bounds.
- [ ] Edge handling avoids obvious halos without inventing content outside the
  validated mask.
- [ ] Copy Image publishes a standards-compatible PNG or image clipboard
  payload on Ubuntu Wayland.
- [ ] Save PNG uses the system file chooser, a safe default name, explicit
  overwrite behavior, and valid PNG output.
- [ ] Cancellation, clipboard failure, encoder failure, invalid masks, and
  unwritable destinations are distinct recoverable outcomes.
- [ ] Temporary buffers and files are released when export completes, fails, is
  cancelled, or the capture session closes.
- [ ] Tests verify dimensions, crop bounds, RGBA pixels, alpha semantics,
  clipboard payloads, PNG decoding, cleanup, and privacy-safe diagnostics.
