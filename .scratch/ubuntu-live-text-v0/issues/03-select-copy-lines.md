# 03: Select and copy recognized lines

**What to build:** A user can inspect recognized lines on the capture surface, select one or more regions, see the same selection in an ordinary selectable text representation, and copy either the selection or the complete OCR result.

**Blocked by:** 02: Recognize a local image with RapidOCR.

**Status:** resolved

- [x] Spatial regions remain aligned while the image is fitted, resized, or zoomed.
- [x] Pointer selection supports one line, contiguous extension, replacement, and clearing.
- [x] The synchronized text representation follows OCR reading order and permits character-level selection.
- [x] Copy Selection and Copy All produce deterministic plain text without hidden metadata.
- [x] Retry, dismiss, and opening another image dispose of the previous capture session.
- [x] State and widget tests cover selection transitions, reading order, clipboard text construction, and session disposal.

## Approved UI direction

- Use a responsive split workspace: dark image-inspection canvas on the left
  and a paper-like recognized-text panel on the right; stack them on narrow
  windows.
- Keep a compact header with the current file/status and explicit Open/New
  image actions.
- Use Ubuntu orange only for primary actions, selected OCR regions, and their
  synchronized text rows.
- Show meaningful reading-order numbers, line count, and OCR duration in the
  results panel.
- Click selects one region, Shift-click extends a contiguous range, and
  clicking empty canvas clears the region selection.
- Keep Copy selection and Copy all persistently available, with short,
  accessible copied feedback.
- Prefer precise spacing, subtle elevation, and restrained transitions; avoid
  gradients, glass effects, oversized cards, and ornamental motion.

## Verification

- Flutter analyzer reports no issues.
- All 73 Flutter tests pass, including responsive layout, resize and zoom
  alignment, pointer and keyboard selection, clipboard behavior, accessibility,
  and capture-session lifecycle coverage.
