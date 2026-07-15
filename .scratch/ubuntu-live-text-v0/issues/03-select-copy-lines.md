# 03: Select and copy recognized lines

**What to build:** A user can inspect recognized lines on the capture surface, select one or more regions, see the same selection in an ordinary selectable text representation, and copy either the selection or the complete OCR result.

**Blocked by:** 02: Recognize a local image with RapidOCR.

**Status:** ready-for-agent

- [ ] Spatial regions remain aligned while the image is fitted, resized, or zoomed.
- [ ] Pointer selection supports one line, contiguous extension, replacement, and clearing.
- [ ] The synchronized text representation follows OCR reading order and permits character-level selection.
- [ ] Copy Selection and Copy All produce deterministic plain text without hidden metadata.
- [ ] Retry, dismiss, and opening another image dispose of the previous capture session.
- [ ] State and widget tests cover selection transitions, reading order, clipboard text construction, and session disposal.
