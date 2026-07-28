# Character Geometry Research for Image-Native Drag Selection

Goal: identify the most credible local path to exact character or text-range
geometry for image-native drag selection, extending the earlier local OCR
engine research rather than repeating engine selection.

## Executive Recommendation

Exact source-image character geometry is not currently available from the
pinned RapidOCR worker path. `return_word_box=True` and
`return_single_char_box=True` expose derived boxes from recognizer columns, not
observed character polygons. Treating those boxes as ground truth would be an
approximation, even when the line polygon is correct.

The most credible next V0 path is a narrow RapidOCR spike that proves or
rejects recognizer-derived per-character boxes as an interaction approximation
against annotated fixtures. The spike should not promise production readiness
and should fail if partial-word dragging, punctuation, whitespace, rotation, or
perspective cannot meet explicit geometry gates.

If the product requirement remains exact character-range geometry, none of the
reviewed local engines supplies it directly:

- RapidOCR and PaddleOCR derive word or character boxes from CTC decoding
  columns inside rectified line crops.
- Tesseract exposes symbol-level rectangles, but not perspective-aware source
  polygons and not explicit whitespace geometry.
- Existing standards can represent text ranges and arbitrary image polygons,
  but they do not create geometry that the OCR engine did not measure.

## Verified Facts

### Current Worker

- The worker dependency file pins Python `>=3.12`, `rapidocr==3.10.0`,
  `onnxruntime==1.31.0`, and `pillow==12.3.0`.
  Source: `worker/pyproject.toml`.
- The current worker adapter imports `RapidOCR`, constructs it with only a log
  level parameter, and maps OCR output into line-level regions with four-point
  polygons and line confidence.
  Source: `worker/src/worker/rapidocr_engine.py`.

### RapidOCR Recognizer and Word-Box Path

- `RapidOCR.__call__` accepts `return_word_box` and
  `return_single_char_box`, then passes `return_word_box` into
  `TextRecInput`.
  Source: [`python/rapidocr/main.py` at `v3.10.0`](https://raw.githubusercontent.com/RapidAI/RapidOCR/v3.10.0/python/rapidocr/main.py).
- The recognizer gets model predictions, decodes them with `CTCLabelDecode`,
  and returns `TextRecOutput` with `txts`, recognition `scores`, and optional
  `word_results`.
  Source: [`python/rapidocr/ch_ppocr_rec/main.py` at `v3.10.0`](https://raw.githubusercontent.com/RapidAI/RapidOCR/v3.10.0/python/rapidocr/ch_ppocr_rec/main.py).
- RapidOCR's CTC decoder obtains `preds_idx = preds.argmax(axis=2)` and
  `preds_prob = preds.max(axis=2)`, removes duplicate and blank columns, joins
  decoded characters into text, and records decoded column positions in
  `WordInfo.word_cols` when word boxes are requested.
  Source: [`python/rapidocr/ch_ppocr_rec/utils.py` at `v3.10.0`](https://raw.githubusercontent.com/RapidAI/RapidOCR/v3.10.0/python/rapidocr/ch_ppocr_rec/utils.py).
- `WordInfo` contains grouped `words`, `word_cols`, `word_types`,
  `line_txt_len`, and per-decoded-character confidences. It does not contain
  detector-observed source-image character polygons.
  Source: [`python/rapidocr/ch_ppocr_rec/typings.py` at `v3.10.0`](https://raw.githubusercontent.com/RapidAI/RapidOCR/v3.10.0/python/rapidocr/ch_ppocr_rec/typings.py).
- RapidOCR calculates word or character boxes after recognition. It computes an
  average CTC column width, derives character cells in the rectified line crop,
  optionally groups all-English/all-number text at word level, adjusts
  overlaps, and maps the derived boxes back through an inverse perspective
  transform.
  Source: [`python/rapidocr/cal_rec_boxes/main.py` at `v3.10.0`](https://raw.githubusercontent.com/RapidAI/RapidOCR/v3.10.0/python/rapidocr/cal_rec_boxes/main.py).
- In the combined output path, `word_results` are only calculated when
  `return_word_box` is enabled, detection boxes exist, and recognizer
  `word_results` are present.
  Source: [`python/rapidocr/main.py` at `v3.10.0`](https://raw.githubusercontent.com/RapidAI/RapidOCR/v3.10.0/python/rapidocr/main.py).

### Tesseract APIs

- Tesseract's `ResultIterator` can return `GetUTF8Text`,
  `Confidence`, and `BoundingBox` at iterator levels including words and
  symbols.
  Source: [Tesseract API example](https://tesseract-ocr.github.io/tessdoc/APIExample.html).
- `PageIterator::BoundingBoxInternal` returns a bounding rectangle in the
  working image coordinate system. For `RIL_SYMBOL`, it uses a blob box or
  connected-component bounding box, then converts to top-down image
  coordinates.
  Source: [Tesseract `PageIterator` API](https://tesseract-ocr.github.io/tessapi/5.x/a02486.html).
- Tesseract exposes `RIL_SYMBOL` text through `ResultIterator::GetUTF8Text`,
  using the current word's best symbol at the current blob index.
  Source: [Tesseract `ResultIterator` API](https://tesseract-ocr.github.io/tessapi/5.x/a02534.html).
- Tesseract exposes raw LSTM timesteps and best LSTM symbol choices for the
  current word, but the API example that prints alternative LSTM choices keeps
  the bounding box at word level.
  Source: [Tesseract API example](https://tesseract-ocr.github.io/tessdoc/APIExample.html).
- Tesseract exposes a line baseline through `PageIterator::Baseline`, including
  a warning that baselines can be vertical with vertical text.
  Source: [Tesseract `PageIterator` API](https://tesseract-ocr.github.io/tessapi/5.x/a02486.html).
- Tesseract's binary image generation notes explicitly say text-line images
  are clipped from the rectangle of the line box and include a TODO to generate
  and use a line polygon.
  Source: [Tesseract `PageIterator` API](https://tesseract-ocr.github.io/tessapi/5.x/a02486.html).
- Tesseract orientation/script detection returns orientation, writing
  direction, textline order, and deskew angle from layout analysis.
  Source: [Tesseract API example](https://tesseract-ocr.github.io/tessdoc/APIExample.html).

### PaddleOCR and PP-OCRv6 APIs

- PaddleOCR's general OCR pipeline documents `return_word_box` as an option to
  return word-level boxes.
  Source: [PaddleOCR OCR pipeline documentation](https://www.paddleocr.ai/v3.7.0/en/version3.x/pipeline_usage/OCR.html).
- PaddleOCR documents `dt_polys` as text detection polygon boxes, each with
  shape `(4, 2)`, and `rec_polys` as confidence-filtered detection boxes in
  the same format.
  Source: [PaddleOCR OCR pipeline documentation](https://www.paddleocr.ai/v3.7.0/en/version3.x/pipeline_usage/OCR.html).
- PaddleOCR documents `rec_boxes` as axis-aligned rectangles derived from
  detection boxes.
  Source: [PaddleOCR OCR pipeline documentation](https://www.paddleocr.ai/v3.7.0/en/version3.x/pipeline_usage/OCR.html).
- PaddleOCR's recognition postprocess groups decoded characters and records
  decoding positions for each grouped word. It treats Chinese characters as
  single-character groups, English and numbers as continuous groups, and many
  punctuation characters as splitters.
  Source: [`ppocr/postprocess/rec_postprocess.py` at `v3.7.0`](https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/v3.7.0/ppocr/postprocess/rec_postprocess.py).
- PaddleX's OCR pipeline calls `cal_ocr_word_box` with recognized text,
  detection polygon, and recognition metadata when `return_word_box` is true,
  then emits `text_word` and `text_word_region`.
  Source: [`paddlex/inference/pipelines/ocr/pipeline.py` at `release/3.7`](https://raw.githubusercontent.com/PaddlePaddle/PaddleX/release/3.7/paddlex/inference/pipelines/ocr/pipeline.py).
- PaddleOCR's text-line orientation classifier is a two-class model for
  `0` and `180` degree line orientation.
  Source: [PaddleOCR text-line orientation documentation](https://www.paddleocr.ai/latest/en/version3.x/module_usage/textline_orientation_classification.html).
- PaddleOCR's document preprocessor includes document orientation
  classification over `0`, `90`, `180`, and `270` degree categories, and a
  separate text image unwarping module.
  Source: [PaddleOCR document preprocessing documentation](https://www.paddleocr.ai/latest/en/version3.x/pipeline_usage/doc_preprocessor.html).

### Standards-Relevant Representation

- W3C Web Annotation defines `TextPositionSelector` for character ranges using
  `start` and `end`, where the start character is included and the end
  character is excluded.
  Source: [Web Annotation Data Model](https://www.w3.org/TR/annotation-model/).
- W3C Web Annotation defines `FragmentSelector` and recommends it as a
  consistent way to describe media fragments such as image regions.
  Source: [Web Annotation Data Model](https://www.w3.org/TR/annotation-model/).
- W3C Media Fragments defines `xywh` spatial fragments, but only rectangular
  selections are supported.
  Source: [Media Fragments URI](https://www.w3.org/TR/media-frags/).
- W3C Web Annotation defines `SvgSelector` for arbitrary image regions such as
  polygons, with the SVG dimensions relative to the source resource.
  Source: [Web Annotation Data Model](https://www.w3.org/TR/annotation-model/).

## Measured Local Observations

- The repository's existing `uv` environment successfully runs the pinned
  RapidOCR and ONNX Runtime dependencies without installing another
  environment.
- On the checked-in OCR image fixture, `return_word_box=True` returns one
  derived word polygon per recognized line.
- On the same fixture, adding `return_single_char_box=True` returns one
  four-point derived box per decoded non-space character. The boxes are not
  uniform subdivisions: their widths and gaps vary with recognizer column
  positions.
- The emitted character boxes remain inside their corresponding line polygons
  on this simple horizontal fixture. This observation does not establish
  accuracy for punctuation, spaces, small fonts, rotation, or perspective.
- The worker tests and adapter currently assert line-level polygons, not word,
  character, or range-level geometry.

## Inferences

- RapidOCR cannot map arbitrary character spans back to source polygons as
  exact observed geometry without a private fork or new alignment layer,
  because the public path records CTC-selected columns, derives average-width
  cells in a rectified crop, and inverse-warps those cells to the source image.
- `return_single_char_box=True` is more useful than equal-width subdivision
  because it uses recognizer column positions, duplicate removal, blanks, and
  line crop geometry. It is still not ground truth for individual glyph ink,
  whitespace extents, kerning, ligatures, or punctuation boundaries.
- Tesseract is the strongest fallback for native symbol rectangles, but those
  rectangles are not enough for exact image-native dragging under rotation and
  perspective. Symbol boxes are rectangles, whitespace is not represented as
  independent glyph geometry, and line-level polygon support is explicitly not
  present in the documented iterator path.
- PaddleOCR and RapidOCR share the same broad limitation for sub-line geometry:
  they expose detected line polygons and recognizer-derived word information,
  not independently detected character polygons.
- W3C Web Annotation is a good vocabulary influence for the output contract:
  use text-position ranges for logical selection and polygon/SVG selectors for
  visual geometry. Media Fragments `xywh` is insufficient for rotated or
  perspective text because it is rectangular.

## Path Comparison

| Path | Geometry fidelity | Whitespace and punctuation | Rotation and perspective | Maintenance risk | Runtime and model impact | Implementation effort |
| --- | --- | --- | --- | --- | --- | --- |
| RapidOCR derived character boxes | Better than equal-width because CTC column positions and line perspective transform are used; not exact source glyph geometry | Spaces are skipped by grouping; punctuation can become splitters or individual decoded characters but is not independently localized | Inherits line detector polygon and inverse transform; failures possible after crop rotation/classification and under curved or highly perspective text | Low if using public API; high if depending on private decoder internals beyond `word_results` | Minimal beyond current worker; enabling word or character boxes adds postprocessing | Small adapter spike plus fixtures; large only if trying to stabilize private internals |
| Tesseract symbol iterator | Real symbol-level rectangles from Tesseract's segmentation path; not quadrilateral or perspective-aware | Symbols exist for recognized blobs; whitespace ranges require interpolation or layout heuristics | OSD supports page orientation and deskew metadata, but arbitrary rotated/perspective scene text remains weak | Low native API risk; higher OCR-quality risk for image-native scene text | Smaller native stack than Paddle/Rapid Python paths | Medium adapter spike; large if paired with external detector |
| PaddleOCR PP-OCRv6 word boxes | Similar derivation family to RapidOCR; documented line polygons and optional word boxes | Recognizer groups English/numbers and treats many punctuation characters as splitters; whitespace is separator, not explicit geometry | Stronger optional document orientation and unwarping modules, but word boxes still derive from line recognition | Medium; larger Python/native stack and more moving parts | Larger runtime; optional orientation/unwarping models add cost | Medium to large for local worker integration |
| Custom detector/recognizer alignment fork | Could expose internal recognizer columns and a calibrated mapping, but still model-alignment approximation unless trained for character boxes | Could define explicit space extents, punctuation spans, and grapheme policies | Can use line polygons and transforms; still needs test gates under perspective | High; private unstable maintenance burden | Depends on fork and exported tensors | Large; not credible as the first V0 step |
| Ground-truth character detector model | Highest if trained or selected for character polygons | Can represent spaces only by policy, since spaces have no ink | Potentially strong if trained on scene text with polygons | High model and data ownership risk | New model family and annotation cost | Very large; outside V0 feasibility unless exact geometry is non-negotiable |

## Proposed Geometry Invariants

- `full_text` is normalized once, and every selectable item references
  half-open character offsets `[start, end)` into that exact string.
- Character offsets count Unicode scalar values or grapheme clusters by an
  explicitly named policy; the policy must be stable across worker and UI.
- Every selectable range stores a `geometry_kind`:
  `observed_polygon`, `derived_ctc_polygon`, `axis_aligned_symbol_rect`, or
  `interpolated_gap`.
- Derived geometry must never be labeled exact. Equal-width subdivision must
  never be labeled ground truth.
- Each visual geometry item stores a four-point polygon in original image pixel
  coordinates, ordered clockwise from visual top-left after all preprocessing
  has been inverted.
- A multi-line range is represented as ordered per-line fragments, not as one
  enclosing polygon.
- Whitespace has explicit policy: either selectable with
  `interpolated_gap` geometry between adjacent non-space spans, or selectable
  logically but not used as a visual hit target. The policy must be visible in
  test fixtures.
- Punctuation is represented as its own range when the recognizer emits it as a
  character; if an engine groups it into a word box, the adapter must mark the
  punctuation geometry as derived.
- Reading order is stored independently from polygon coordinates and must be
  testable for columns, menus, and mixed UI layouts.
- Every emitted geometry item carries provenance: engine, version, model id if
  available, source line polygon id, and derivation method.

## Fixture Categories

- Horizontal Ubuntu UI text: menus, dialogs, terminal, editor, browser, mixed
  font sizes, light and dark themes.
- Partial-word selections: prefixes, suffixes, middle substrings, camelCase,
  snake_case, dotted identifiers, and numeric ranges.
- Punctuation: URLs, paths, decimals, quotes, parentheses, hyphens, slashes,
  ellipses, and trailing punctuation.
- Whitespace: multiple spaces, tabs rendered in monospace text, leading and
  trailing spaces in terminal-like regions, and line breaks.
- Multi-line ranges: drag from middle of one line into the next, including
  ragged line ends.
- Rotation: full-frame cardinal rotation, per-line `180` rotation, and modest
  arbitrary line angles.
- Perspective: monitor or phone photos with trapezoid text regions and
  screenshot-like content.
- Small text: low-height UI labels, antialiased text, scaled desktop fonts,
  and compressed captures.
- Failure controls: low contrast, blur, decorative fonts, mixed scripts, and
  intentionally ignored or illegible regions.

## Unresolved Questions

- What numeric gate makes a derived character box acceptable for V0 dragging:
  polygon IoU, centerline error, edge error, or user-task success?
- Should spaces be draggable as logical text only, or should the UI show a
  visible gap target between adjacent characters?
- Should the selection unit be Unicode scalar value, extended grapheme cluster,
  or engine-emitted character token?
- How should the UI behave when OCR emits a ligature, combines accents, or
  splits a visual glyph into multiple decoded characters?
- Is PP-OCRv6 small accurate enough on the actual Ubuntu fixture set when
  character boxes are requested, or does requesting word boxes change runtime
  enough to matter?
- Is exact geometry a hard product invariant, or can V0 explicitly ship
  derived geometry with user-visible caveats and fixture-backed bounds?

## Recommended Next V0 Spike for Issue 05

Run a bounded RapidOCR character-geometry spike using the existing pinned
worker stack and a small annotated fixture set.

### Spike Scope

- Enable `return_word_box=True` and `return_single_char_box=True` in a local
  experimental adapter path.
- Preserve the current line polygon output and add experimental per-character
  range fragments with `geometry_kind=derived_ctc_polygon`.
- Do not change the production worker contract unless the spike passes.
- Use only fixed local fixtures; disable any runtime downloads.
- Compare derived character polygons to hand-annotated character or
  character-range polygons for representative text classes.

### Pass Gates

- Partial-word ranges inside ordinary horizontal UI text select the intended
  characters with no systematic off-by-one errors.
- Punctuation ranges are separately addressable for URLs, paths, decimals, and
  code-like identifiers.
- Multi-line drag ranges preserve reading order and produce separate per-line
  fragments.
- Derived geometry stays within an agreed pixel or IoU tolerance on the
  horizontal UI fixture set.
- Rotation and perspective fixtures are either within tolerance or clearly
  marked as fail cases with no misleading exactness label.
- The adapter can represent whitespace according to the chosen whitespace
  policy without pretending space geometry was observed.

### Fail Gates

- Any implementation relies on equal-width subdivision as ground truth.
- RapidOCR does not emit stable character results for common punctuation or
  partial-word selections.
- Derived boxes visibly drift under modest rotation or perspective beyond the
  selected gate.
- Whitespace cannot be represented consistently enough for drag semantics.
- Accessing the necessary data requires monkeypatching private internals in a
  way that cannot be pinned to public source references.

### Go/No-Go Outcome

- Go: keep RapidOCR for V0 image-native drag selection only as
  fixture-bounded derived geometry, with explicit provenance and approximation
  labels in the contract.
- No-go: keep RapidOCR line OCR for V0 text extraction, but do not claim exact
  character dragging; either reduce V0 to word or line selection, or open a new
  spike for Tesseract symbol rectangles and a separate spike for a true
  character-geometry model.

