# 05: Validate character-range geometry

**What to build:** Maintainers can determine which local OCR path produces
character or text-range geometry reliable enough for direct image selection,
without treating estimated equal-width boxes as ground truth.

**Blocked by:** 02: Recognize a local image with RapidOCR.

**Status:** resolved

- [x] Non-sensitive fixtures cover proportional and monospace fonts,
  punctuation, URLs, code, repeated whitespace, small text, rotation, and
  perspective.
- [x] The spike inspects RapidOCR recognizer outputs and measures whether
  character ranges can be mapped back to source-image polygons.
- [x] An independent fallback is only required on a RapidOCR no-go. RapidOCR
  passed the fixed horizontal gates, so no fallback was opened.
- [x] Character text, ordering, containment, overlap, baseline direction, and
  source-image polygon invariants are explicit and tested.
- [x] Geometry provenance is engine-neutral: recognizer boxes are
  `derived_ctc_polygon`; logical spaces are `interpolated_gap`.
- [x] Invalid or ambiguous character geometry preserves the corresponding line
  and synchronized selectable text; it never creates misleading hit targets.
- [x] The result recommends a V0 adapter with evidence or blocks issue 06 with
  a precise technical reason.

**Decision:** GO for exact ranges in the recognized transcript, using
RapidOCR-derived polygons as approximate hit geometry. Repeated source spaces
may be normalized, and polygons must never be presented as exact glyph
outlines. See `../evidence/character-geometry.md`.
