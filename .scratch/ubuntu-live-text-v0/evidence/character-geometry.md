# Character geometry spike evidence

**Decision:** GO

Use RapidOCR-derived CTC polygons as approximate hit geometry for exact ranges in recognized text.

## Fixed gates

- Required horizontal fixtures: code, proportional, punctuation/URL, small text.
- Minimum token coverage: 95%.
- Minimum annotated-center hit rate: 95%.
- Zero ordering inversions and zero invalid horizontal lines.
- Valid source bounds and explicit geometry provenance.
- Internally consistent logical whitespace ranges.
- Rotation and perspective reported separately.

## Results

- **code:** transcript=True, coverage=100.0%, center-hit=100.0%, ordering-errors=0, invalid-lines=0, baseline-error=0.15°
- **perspective:** transcript=True, coverage=100.0%, center-hit=100.0%, ordering-errors=0, invalid-lines=0, baseline-error=0.36°
- **proportional:** transcript=True, coverage=100.0%, center-hit=95.0%, ordering-errors=0, invalid-lines=0, baseline-error=0.16°
- **punctuation-url:** transcript=True, coverage=100.0%, center-hit=96.3%, ordering-errors=0, invalid-lines=0, baseline-error=0.00°
- **repeated-spaces:** transcript=False, coverage=55.6%, center-hit=55.6%, ordering-errors=0, invalid-lines=0, baseline-error=0.29°
- **rotated:** transcript=True, coverage=100.0%, center-hit=100.0%, ordering-errors=0, invalid-lines=0, baseline-error=0.11°
- **small-text:** transcript=True, coverage=100.0%, center-hit=100.0%, ordering-errors=0, invalid-lines=0, baseline-error=1.21°

## Interpretation

- RapidOCR's public single-character output passed the fixed horizontal interaction gates.
- Character polygons are derived from CTC recognizer columns. They are approximate hit targets, not exact glyph outlines.
- The repeated-space fixture was recognized with one space instead of three. Ranges remain exact for the recognized transcript; source spacing is not guaranteed.
- Rotated and perspective fixtures are diagnostics only; both are listed above and were not used to make the horizontal pass decision.
- A fallback OCR engine is not required by this spike because the primary path passed. The production line-only contract remains unchanged until issue 06.

## V0 decision

Proceed to issue 06 with an engine-neutral range contract that preserves `derived_ctc_polygon` and `interpolated_gap` provenance. Keep line text selectable whenever range geometry is unavailable or invalid.

## Runtime

- python: 3.12.3
- rapidocr: 3.10.0
- onnxruntime: 1.31.0
