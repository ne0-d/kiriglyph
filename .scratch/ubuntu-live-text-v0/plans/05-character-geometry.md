# Character Geometry Spike Implementation Plan

> **For agentic workers:** execute one red-green slice at a time. This is an
> evidence spike, not permission to change the production OCR protocol.

**Goal:** Prove or reject RapidOCR's public recognizer-derived character boxes
as bounded hit geometry for V0 image-native text dragging.

**Architecture:** Keep the production line-only adapter unchanged. Add a small
experimental Python module that calls the pinned RapidOCR public API with
single-character boxes, maps decoded tokens to half-open text ranges, labels
their provenance, validates invariants, and scores them against deterministic
non-sensitive fixtures. Only a passing evidence report can authorize a later
contract change.

**Tech stack:** Python 3.12, RapidOCR 3.10, ONNX Runtime CPU, Pillow, pytest,
JSON fixtures.

## Global constraints

- Never label derived CTC geometry as observed or exact glyph geometry.
- Never use equal-width subdivision as ground truth.
- Keep all inference local and prevent runtime downloads.
- Preserve the current line result whenever character geometry is incomplete or
  invalid.
- Use Unicode code-point offsets in the spike and record the future need for a
  cross-language grapheme-cluster policy.
- Represent spaces logically as half-open text ranges. A visible gap polygon
  may be marked `interpolated_gap`; it is never an observed glyph.
- Do not change `contracts/v1`, Flutter models, or the production worker
  response during this spike.
- Run individual tests with a 60-second limit and the final Python suite with a
  120-second limit.
- Do not create commits; the user owns commits.

---

### Task 1: Deterministic annotated fixtures

**Files:**
- Create: `worker/tests/character_geometry_fixture_factory.py`
- Create: `worker/tests/test_character_geometry_fixtures.py`
- Generate: `fixtures/worker/character-geometry/*.png`
- Generate: `fixtures/worker/character-geometry/*.json`

**Public seam:** `build_character_geometry_fixtures(output_directory: Path)`
produces deterministic PNG images and JSON annotations containing source text,
line polygons, character ranges, advance-cell polygons, and transformation
metadata.

- [ ] Write a failing test requiring horizontal proportional text,
  monospace/code, punctuation/URL, repeated spaces, small text, rotation, and
  perspective fixtures.
- [ ] Verify the test fails because the fixture factory does not exist.
- [ ] Implement the minimum Pillow fixture factory using a repository-available
  redistributable font, fixed canvas sizes, fixed colors, and deterministic
  transforms.
- [ ] Record half-open code-point ranges. Keep whitespace ranges in annotations
  even though whitespace has no ink box.
- [ ] Generate the fixtures and assert every polygon is finite, clockwise,
  within image bounds, ordered, and reproducible byte-for-byte.
- [ ] Run only `worker/tests/test_character_geometry_fixtures.py`.

### Task 2: Experimental RapidOCR character output

**Files:**
- Create: `worker/src/worker/character_geometry_probe.py`
- Create: `worker/tests/test_character_geometry_probe.py`

**Public seam:**

```python
probe_character_geometry(image_path: Path) -> CharacterGeometryProbeResult
```

The result contains recognized line text, line polygons, ordered character
fragments, half-open code-point ranges, `derived_ctc_polygon` provenance,
confidence, and timings. Invalid lines contain a reason and no selectable
character fragments.

- [ ] Write a failing test proving a simple horizontal fixture emits ordered
  non-space fragments whose concatenated tokens match normalized OCR text.
- [ ] Implement the public RapidOCR call with `return_word_box=True` and
  `return_single_char_box=True`; do not access private decoder fields.
- [ ] Write failing tests for punctuation and code-like identifiers.
- [ ] Map each emitted token to the next exact occurrence in the recognized
  line and reject ambiguous or missing alignments rather than guessing.
- [ ] Write a failing repeated-whitespace test.
- [ ] Emit logical whitespace ranges between adjacent matched tokens and mark
  any visual gap polygon `interpolated_gap`.
- [ ] Add tests proving malformed, out-of-bounds, non-finite, overlapping, or
  transcript-inconsistent geometry invalidates only that line.
- [ ] Run only `worker/tests/test_character_geometry_probe.py`.

### Task 3: Geometry scoring and pass/fail gates

**Files:**
- Create: `worker/src/worker/character_geometry_metrics.py`
- Create: `worker/tests/test_character_geometry_metrics.py`

**Public seam:**

```python
score_character_geometry(
    expected: AnnotatedFixture,
    actual: CharacterGeometryProbeResult,
) -> CharacterGeometryScore
```

The score reports transcript coverage, token coverage, ordering violations,
center-hit rate, normalized boundary error, polygon containment, and results by
fixture category.

- [ ] Write failing worked-example tests for every metric using literal
  polygons whose expected scores can be calculated independently.
- [ ] Implement polygon normalization, centers, point containment, and
  normalized edge errors without adding a geometry dependency.
- [ ] Score the pinned fixtures and serialize deterministic machine-readable
  results.
- [ ] Apply these V0 interaction gates:
  - all required horizontal fixtures preserve exact recognized token order;
  - every emitted fragment has valid provenance and source bounds;
  - at least 95% of annotated non-space character centers fall inside their
    predicted fragment;
  - punctuation and code fixture token coverage is at least 95%;
  - no reading-order inversions occur;
  - whitespace policy is internally consistent;
  - rotation and perspective results are reported separately and cannot be
    silently counted as horizontal passes.
- [ ] Keep the thresholds in one named policy object so evidence can revise
  them without changing metric algorithms.
- [ ] Run only `worker/tests/test_character_geometry_metrics.py`.

### Task 4: Evidence and decision

**Files:**
- Create: `.scratch/ubuntu-live-text-v0/evidence/character-geometry.json`
- Create: `.scratch/ubuntu-live-text-v0/evidence/character-geometry.md`
- Modify: `.scratch/ubuntu-live-text-v0/issues/05-character-geometry.md`

- [ ] Run the probe and scorer through a deterministic command using the
  existing locked `uv` environment.
- [ ] Record per-category evidence, failed fixtures, model/runtime identity,
  limitations, and whether the gates passed.
- [ ] If gates pass, recommend a later engine-neutral range contract with
  explicit `derived_ctc_polygon` and `interpolated_gap` provenance.
- [ ] If gates fail, keep the production protocol unchanged and recommend the
  next bounded fallback spike; do not weaken thresholds after seeing results.
- [ ] Mark issue 05 resolved only when the report contains a clear go/no-go
  decision and every checklist item has evidence.

### Task 5: Regression verification

- [ ] Format and lint the new Python files with the repository's configured
  tools where available.
- [ ] Run:
  `timeout 120s .tools/uv-bin/uv run --project worker pytest worker/tests -q`.
- [ ] Run Flutter tests only if shared contracts or app files changed; they
  should not change during this spike.
- [ ] Check IDE diagnostics, `git diff --check`, fixture determinism, and that
  no runtime network request occurred.
