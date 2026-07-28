# Character Drag Selection Implementation Plan

> **For agentic workers:** execute one red-green slice at a time. Do not run
> open-ended test loops or create commits; the user owns commits.

**Goal:** Let users select and copy exact recognized character ranges directly
on the captured image, including backward and multiline dragging.

**Architecture:** RapidOCR's validated recognizer-derived fragments become an
engine-neutral nested line contract. Flutter keeps one immutable document
selection model and renders source-image range polygons through the existing
fit/zoom transform. Range-enabled lines receive character gestures; invalid
lines retain the existing line and selectable-panel fallback.

**Tech stack:** Python 3.12, RapidOCR 3.10, JSON Schema Draft 2020-12, Dart,
Flutter, Riverpod, CustomPainter, Flutter widget tests, pytest.

## Global constraints

- Geometry is `derived_ctc_polygon` or `interpolated_gap`; never label it as an
  exact glyph outline.
- Exact copied text means the recognized transcript. Source whitespace may
  have been normalized by OCR.
- V0 offsets are Unicode code-point offsets.
- One invalid range set disables character geometry only for that line.
- Equal-width character subdivision is forbidden.
- Character painting and hit testing derive from the same source-image
  transform.
- A primary drag starting on text selects; a drag starting outside text pans
  when zoomed.
- Preserve ordinary selectable text as the accessibility fallback.
- Targeted tests use a 60-second limit; complete suites use 120 seconds.
- Do not create commits.

---

### Task 1: Production character-range contract and RapidOCR adapter

**Files:**
- Create: `contracts/v1/character-range.schema.json`
- Modify: `contracts/v1/region.schema.json`
- Modify: `worker/src/worker/rapidocr_engine.py`
- Modify: `worker/tests/test_contracts.py`
- Modify: `worker/tests/test_rapidocr_engine.py`
- Modify: `worker/tests/test_worker_process.py`

**Interfaces:**
- A line region contains required `ranges: list[CharacterRange]`.
- A range contains `start`, `end`, `text`, `polygon`, `geometry_kind`, and
  nullable `confidence`.
- `RapidOcrEngine.recognize(...)` continues returning the existing result shape
  with nested ranges added.

- [ ] Add a schema test with one valid derived character and one interpolated
  space, plus invalid provenance, offsets, polygon, confidence, and extra-key
  cases.
- [ ] Run the contract test and confirm RED because the range schema and region
  property do not exist.
- [ ] Add the range schema and make `ranges` required on every line.
- [ ] Rerun the contract test and confirm GREEN.
- [ ] Add adapter tests proving the real fixture returns contiguous ranges that
  reconstruct each line and carry only approved provenance.
- [ ] Add an adapter unit test with malformed geometry for one line and valid
  geometry for another; require `ranges: []` only on the malformed line.
- [ ] Run the adapter tests and confirm RED because production inference does
  not request or map character output.
- [ ] Call RapidOCR with public single-character output flags and map fragments
  through the validated geometry mapper. Catch geometry failures per line and
  preserve line output with an empty range list.
- [ ] Update worker test stubs with `ranges: []`.
- [ ] Run:
  `timeout 60s .tools/uv-bin/uv run --project worker pytest worker/tests/test_contracts.py worker/tests/test_rapidocr_engine.py worker/tests/test_worker_process.py -q`.

### Task 2: Strict Dart range parsing

**Files:**
- Modify: `app/lib/ocr/ocr_result.dart`
- Modify: `app/lib/protocol/worker_protocol.dart`
- Modify: `app/test/worker_protocol_test.dart`
- Modify Dart test payloads that represent protocol responses.

**Interfaces:**
- `CharacterRange` exposes code-point offsets, exact text, polygon,
  `GeometryKind`, and optional confidence.
- `TextRegion.ranges` is immutable and defaults to empty only for direct test
  construction; protocol payloads must include it.

- [ ] Add parser tests for a valid line with punctuation and whitespace ranges.
- [ ] Add parser rejection tests for gaps/overlap, text reconstruction
  mismatch, invalid provenance, invalid confidence, malformed/out-of-image
  polygons, and extra fields.
- [ ] Run `worker_protocol_test.dart` and confirm RED because ranges are not
  parsed.
- [ ] Add immutable range models and strict parsing. Validate offsets in
  Unicode code points, contiguous coverage, exact reconstruction, polygon
  bounds, and approved provenance.
- [ ] Update response fixtures with explicit empty ranges.
- [ ] Run:
  `timeout 60s ../.tools/flutter/bin/flutter test test/worker_protocol_test.dart -r expanded`
  from `app/`.

### Task 3: One document-level character selection model

**Files:**
- Modify: `app/lib/selection/region_selection.dart`
- Modify: `app/lib/selection/region_selection_provider.dart`
- Modify: `app/test/region_selection_test.dart`
- Modify: `app/test/region_selection_session_test.dart`

**Interfaces:**
- `TextPosition(regionId, offset)` identifies a code-point boundary.
- `selectCharacter(regionId, offset)` selects one recognized character.
- `startAt(position)` and `extendToPosition(position)` preserve directional
  anchor/focus.
- `moveHorizontal`, `moveVertical`, and `selectAll` return new immutable state.
- Existing `select` and `extendTo` keep line fallback behavior.

- [ ] Add failing pure tests for partial words, punctuation, one/multiple
  spaces, forward/backward multiline selection, replacement, extension,
  clearing, and newline construction.
- [ ] Add failing tests for left/right movement, line crossing, up/down
  clamping, Shift extension, select-all, and lines without geometry.
- [ ] Implement the minimum boundary-based immutable model using code-point
  slicing; widgets must not build copied substrings.
- [ ] Keep `isSelected(regionId)` for synchronized row/line state and add
  `isRangeSelected(regionId, start, end)` for painting.
- [ ] Add controller methods matching the pure model and prove a new OCR result
  resets selection.
- [ ] Run:
  `timeout 60s ../.tools/flutter/bin/flutter test test/region_selection_test.dart test/region_selection_session_test.dart -r expanded`
  from `app/`.

### Task 4: Source-image hit resolution and pointer dragging

**Files:**
- Modify: `app/lib/ui/workspace/fitted_image_geometry.dart`
- Create: `app/lib/ui/workspace/character_hit_test.dart`
- Create: `app/lib/ui/workspace/character_line_target.dart`
- Create: `app/lib/ui/workspace/character_range_painter.dart`
- Modify: `app/lib/ui/workspace/capture_canvas.dart`
- Modify: `app/test/fitted_image_geometry_test.dart`
- Create: `app/test/character_hit_test_test.dart`
- Modify: `app/test/result_workspace_test.dart`
- Modify: `app/test/support/workspace_harness.dart`

**Interfaces:**
- `FittedImageGeometry.rangePolygon/rangeRect` map character geometry.
- `CharacterHitTest.resolve(sourcePoint)` returns the nearest validated
  character and boundary.
- `CharacterLineTarget` owns gestures for one range-enabled line.

- [ ] Add failing geometry tests for mapped character polygons and inverse
  display-to-source mapping.
- [ ] Implement those transforms and rerun GREEN.
- [ ] Add literal-polygon hit tests for character centers, leading/trailing
  boundaries, whitespace, rotation, nearest-line resolution, and no-hit empty
  space.
- [ ] Implement deterministic polygon containment and baseline projection.
- [ ] Add widget tests that tap one character and drag partial, backward, and
  multiline ranges; assert synchronized row state and exact copy text.
- [ ] Add resize and zoom tests proving highlights and hits stay aligned.
- [ ] Render character highlights and line-level fallback targets. Gesture
  updates resolve through `TransformationController.toScene`, then the fitted
  geometry inverse. Keep InteractiveViewer panning available outside text
  targets.
- [ ] Run:
  `timeout 60s ../.tools/flutter/bin/flutter test test/fitted_image_geometry_test.dart test/character_hit_test_test.dart test/result_workspace_test.dart -r expanded`
  from `app/`.

### Task 5: Keyboard, clipboard, semantics, and acceptance

**Files:**
- Modify: `app/lib/ui/workspace/capture_canvas.dart`
- Modify: `app/lib/ui/workspace/recognized_text_panel.dart`
- Modify: `app/lib/ui/workspace/recognized_text_row.dart`
- Modify: `app/test/result_workspace_test.dart`
- Modify: `.scratch/ubuntu-live-text-v0/issues/06-character-drag-selection.md`
- Modify: `.local/project-learning-guide.md`

**Interfaces:**
- Arrow keys dispatch selection movement; Shift controls extension.
- Ctrl+A selects all; Ctrl+C uses the same selected text as the copy button;
  Escape clears selection.

- [ ] Add failing widget tests for horizontal/vertical movement, Shift
  extension, Ctrl+A, Ctrl+C, Escape, fallback lines, semantics state, clipboard
  failure retention, and compact/wide layouts.
- [ ] Add a focusable canvas action layer and route every command through the
  selection controller.
- [ ] Keep copy feedback short and content-safe; report selected character or
  line counts without announcing recognized content.
- [ ] Run the complete Issue 06 widget test file with a 60-second timeout.
- [ ] Format changed Dart and Python files with repository-available formatters.
- [ ] Run `timeout 60s ../.tools/flutter/bin/flutter analyze` from `app/`.
- [ ] Run `timeout 120s ../.tools/flutter/bin/flutter test -r expanded` from
  `app/`.
- [ ] Run
  `timeout 120s .tools/uv-bin/uv run --project worker pytest worker/tests -q`.
- [ ] Run `timeout 120s ../.tools/flutter/bin/flutter build linux --debug` from
  `app/`.
- [ ] Check IDE diagnostics, fixture determinism, `git diff --check`, and that
  `.local/project-learning-guide.md` remains ignored.
- [ ] Mark Issue 06 resolved only when each acceptance item has passing
  evidence.
