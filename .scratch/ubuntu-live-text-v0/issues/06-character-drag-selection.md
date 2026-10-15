# 06: Drag across exact text ranges

**What to build:** A user can press and drag directly across recognized
characters on an image, including partial words and multiple lines, and copy
the exact selected substring.

**Blocked by:** 05: Validate character-range geometry.

**Status:** resolved

- [x] Pointer-down resolves the nearest validated character boundary and drag
  updates one anchored range in reading order.
- [x] Selection supports partial words, punctuation, whitespace, multiline
  ranges, backward dragging, replacement, extension, and clearing.
- [x] One and two nearby primary clicks select the character and Unicode
  word/run. Three nearby primary clicks now select the complete paragraph when
  paragraph grouping is available, falling back to the OCR line.
- [x] Highlight polygons remain aligned while fitted, resized, zoomed, or
  panned and never imply character precision where geometry is unavailable.
- [x] Copied text preserves exact characters and sensible source whitespace
  without hidden metadata.
- [x] Arrow keys move by character; Shift+arrows extend the same range exposed
  to pointer users.
- [x] Lines without validated character geometry remain available through the
  synchronized standard selectable text representation.
- [x] State, geometry, pointer, keyboard, clipboard, accessibility, and
  responsive widget tests cover the complete interaction.

**Resolution evidence:** The production worker emits validated engine-neutral
ranges or an empty per-line fallback. Flutter supports direct partial,
backward, multiline, zoom-safe dragging; exact recognized-text copy; line
fallbacks; arrow and Shift+arrow movement; Ctrl+A/C; Escape clearing; and
accessible line semantics. Degenerate OCR whitespace receives an explicitly
interpolated minimum-width gap, while unusable geometry still disables only
its line. Final verification passed: 116 Flutter tests, 60 Python tests,
`flutter analyze`, the Linux debug build, IDE diagnostics, and
`git diff --check`. The follow-up click gestures passed 49 relevant Flutter
tests plus fresh analyzer, IDE-diagnostic, and diff checks.

## Approved design

### Architecture

Extend each engine-neutral line region with an ordered `ranges` array. Each
range contains line-local half-open Unicode code-point offsets, its exact text,
a source-image quadrilateral, optional confidence, and one of these geometry
provenance values:

- `derived_ctc_polygon` for RapidOCR recognizer-derived character geometry;
- `interpolated_gap` for logical whitespace between recognized characters.

An empty `ranges` array means precise image selection is unavailable for that
line. The line text and line polygon remain valid and selectable. The
production adapter must validate each line independently and must never expose
partial or misleading range geometry.

Flutter parses this contract into immutable range models. One document-level
`CharacterSelection` module owns the anchor, focus, reading order, selected
fragments, copied text, and keyboard movement. Widgets send positions and
commands to this module rather than constructing substrings themselves.

### Pointer interaction

- A primary-button press on validated character geometry starts a new
  selection at the nearest boundary of that character.
- Dragging updates the focus boundary through reading order, including
  backward and multiline movement.
- A primary drag that starts on empty image space pans the image when zoomed.
- One click on validated character geometry selects that character.
- Two nearby clicks select the Unicode word containing that character;
  punctuation and whitespace select their own contiguous runs.
- Three nearby clicks select the complete paragraph when paragraph grouping is
  available, falling back to the complete OCR line.
- Starting another character drag replaces the current range.
- Clicking empty canvas space without panning clears the selection.
- Lines with unavailable geometry retain the existing line interaction and
  synchronized standard selectable-text fallback.

Pointer hit resolution uses source-image polygons and the same
`FittedImageGeometry` transform as image painting. It does not cache
screen-space boxes, so resize, zoom, and pan cannot desynchronize highlights.

### Selection and copying

The selection is normalized only for reading and painting; its original anchor
and focus are retained so reverse dragging and Shift-extension remain stable.
Selected text is assembled from recognized range text. A newline is inserted
between selected lines. Punctuation and recognized spaces are copied exactly;
no markup, coordinates, or hidden metadata enter the clipboard.

RapidOCR may normalize source whitespace, so “exact” means exact characters in
the recognized transcript. V0 range offsets use Unicode code points.
Unsupported multi-code-point recognizer tokens invalidate range geometry for
that line and preserve the line fallback instead of guessing grapheme
boundaries.

### Keyboard and accessibility

- Left and Right move one recognized character through document reading order.
- Up and Down move to the nearest available offset on the adjacent selectable
  line, clamped when that line is shorter.
- Holding Shift extends from the existing anchor; movement without Shift
  replaces the selection with the destination character.
- Ctrl+A selects all recognized text, Ctrl+C copies the current selection, and
  Escape clears it while the result remains open.
- The canvas exposes the selected transcript and selection state through
  Flutter semantics. Lines without character geometry remain accessible in the
  standard selectable text panel.

### Failure behavior

- One malformed, incomplete, overlapping, out-of-bounds, or
  transcript-inconsistent range set disables precise geometry only for its
  source line.
- A line-level fallback never prevents other valid lines from supporting
  character dragging.
- Clipboard failures retain the selection and use the existing visible,
  accessible failure feedback.
- Character geometry is optional data in the line model, not a second OCR
  result that can disagree with line text.

### Approaches considered

1. **Chosen:** nested engine-neutral ranges plus one document-level
   anchor/focus model. This keeps OCR details behind the worker contract and
   centralizes multiline selection behavior.
2. Independent selection state per line. Rejected because backward multiline
   ranges, newline construction, and keyboard extension would be duplicated
   across widgets.
3. Custom Flutter selectable render objects. Rejected for V0 because it couples
   OCR polygons to Flutter text-rendering internals and adds disproportionate
   complexity before the interaction has passed acceptance testing.

### Verification

- Contract and worker tests cover exact offsets, provenance, bounds,
  containment, ordering, whitespace, and per-line invalidation.
- Dart parser tests reject malformed or inconsistent range data.
- Pure state tests cover partial words, punctuation, spaces, forward and
  backward multiline ranges, replacement, extension, clearing, and copied
  text.
- Geometry tests cover nearest-boundary resolution and mapping under fit,
  resize, zoom, and pan.
- Widget tests cover pointer dragging, empty-space panning, line fallback,
  highlighting, keyboard movement, clipboard actions, responsive layouts, and
  semantics.
- Targeted tests run with bounded timeouts before the complete Python and
  Flutter suites.
