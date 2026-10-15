# 19: Circle to select text

**What to build:** In the overlay and workspace, a drag that starts off text
draws a freehand circle and selects the text inside it.

**Blocked by:** 18: Selection overlay on the active display

**Status:** resolved (manual acceptance passed; paragraph snapping and triple-click paragraph added after testing)

- [x] A drag starting on text keeps character selection; a drag starting off
  text draws a visible stroke that fades after release.
- [x] On release, every character whose geometry centre lies inside the closed
  stroke is selected, in reading order, with the smooth highlight.
- [x] An empty circle clears the selection without error.
- [x] Copy produces the selected text with line breaks between lines.

## Implementation notes

The released stroke is simplified and interpreted as an even-odd closed
polygon in source-image coordinates, so zoom and full-bleed overlay placement
do not change selection. OCR lines are grouped into paragraphs in source-image
coordinates when their vertical gap is at most
`paragraphMaxVerticalGapHeightRatio = 0.9` of the smaller line height, their
height ratio is at most `paragraphMaxLineHeightRatio = 1.5`, their horizontal
overlap ratio is at least `paragraphMinHorizontalOverlapRatio = 0.35`, and
their left edges align within
`paragraphLeftAlignmentToleranceHeightRatio = 1.5` line heights or form a
plausible continuation indent up to
`paragraphMaxContinuationIndentHeightRatio = 4.0` line heights.

Circle selection now snaps to whole paragraphs when at least
`paragraphSnapCharacterFractionThreshold = 0.2` of paragraph characters are
inside the loop, or when a complete line is enclosed
(`paragraphSnapCompleteLineFraction = 1.0`). Below that, touched lines snap
whole when at least `lineSnapCharacterFractionThreshold = 0.5` of their
characters are inside; otherwise the old first-to-last matched character
extent is kept for that line. Whole-line snapping keeps the smooth band
highlight end to end. Lines without hits are skipped by an explicit per-line
selection range.

Tiny off-text strokes are treated as plain empty-canvas clicks and clear the
selection when the path is under 12 logical pixels or has near-zero area. The
stroke fades for 300 ms after release, or clears immediately when reduced
motion disables animations. Copy selection formats paragraph-aware selections
with one newline between lines in the same paragraph and a blank line between
different paragraphs. `RegionSelection.selectedText` remains the plain
single-newline transcript for selection-state and panel semantics.
