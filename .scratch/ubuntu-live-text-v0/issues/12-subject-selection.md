# 12: Select a subject in the overlay by click or drawn region

**What to build:** In the selection overlay, a user can click a visible subject
or draw around it, inspect the resulting mask on the
frozen screen, and refine or clear it without sending pixels off-device.

**Blocked by:** 11: Select a local interactive segmentation adapter.

**Status:** implemented — UI slice covered by automated tests; real GNOME,
real-model feel, and multi-display fractional-scale checks remain manual
verification items for 14.

- [x] The overlay supports text and subject selection in one interface.
  Text gestures keep their behavior; object selection uses click and
  drawn-region prompts.
- [x] One image embedding is computed per capture, started right after the crop
  so it is ready by the time the user switches modes, reused within the
  session, and discarded when the overlay is dismissed.
- [x] A click supplies a point prompt; a drawn region supplies a bounded lasso or
  box prompt understood by the model-neutral adapter.
- [x] Add, remove, refine, replace, and clear interactions produce deterministic
  prompt state with short progress and cancellation behaviour.
- [x] The mask is drawn over the frozen pixels with a clear outline and stays
  aligned at any display scale.
- [x] Empty, unstable, edge-touching, and multi-subject masks have clear
  recoverable outcomes.
- [x] Pointer, keyboard, semantics, state, geometry, cancellation, and
  responsive widget tests cover the workflow.

## Backend slice (done)

Delivered:

- A separate `worker.segmentation_worker` process using the existing v1 NDJSON
  envelope and request IDs, with `embed`, `prompt`, `cancel`, and `close`.
- A shipped EfficientSAM-Ti adapter behind the model-neutral segmentation
  contract, including point, background-point, box, and polygon/lasso prompts.
  Lasso prompts lower to a bounding box plus deterministic inside samples.
- Private `0600` alpha PNG mask files under the runtime directory, returned as
  path, byte length, and SHA-256; files are cleaned up when the session closes.
- Mask outcomes and stats for `ok`, `empty`, `suspect_full_image`,
  edge-touching, connected components, largest component bounds, confidence,
  and timings.
- Typed failures for cancellation, timeout, malformed output, model load,
  missing model files, process death, out-of-memory, and closed sessions.
- `kiriglyph-fetch-models` as the explicit model download command; runtime
  segmentation performs no network access.
- Dart `SubjectSegmenter` and `ProcessSubjectSegmenter` ports plus a fake test
  implementation for the overlay UI agent.

Protocol summary:

| Request | UI-facing purpose |
| --- | --- |
| `embed` | Start once after the private crop is available; keep the returned handle for the overlay session. |
| `prompt` | Send the full current prompt state and receive a mask result/statistics. |
| `cancel` | Mark an in-flight request as unwanted; ORT work may finish internally and be discarded. |
| `close` | End the session, drop embeddings, delete mask files, and let Dart kill the child if needed. |

UI slice delivered:

- Unified overlay interaction without a Text/Subject toolbar toggle.
- Successful OCR with zero text regions keeps the frozen overlay open in Text
  overlay, announces `No text found - click or draw around an object`, disables
  text copy actions with no-text tooltips, and starts the
  same single subject embedding used by normal ready sessions.
- Subject prompt state model with immutable `replacePoint`, `addForeground`,
  `addBackground`, `replaceRegion`, `undo`, and `clear` transitions.
- Source-image point and lasso prompt mapping, covered at 1.0 and 1.25 fitted
  image scales.
- One post-OCR embedding future per overlay session, latest pending prompt held
  while preparing, prompt cancellation on Clear/new prompt, and segmenter close
  when the overlay session is dismissed.
- Alpha mask rendering over the frozen frame with tinted fill plus black/white
  offset mask outlines. Suspect-full-image results are rejected instead of
  accepted as the current mask.
- Recoverable status text for empty, suspect-full-image, edge-touching,
  multiple-component, model-missing, timeout, worker, malformed-output,
  out-of-memory, and model-load failures. `kiriglyph-fetch-models` is shown for
  missing models.

Manual verification pending in 14:

- Real EfficientSAM-Ti interaction feel and latency.
- GNOME Wayland one- and multi-display alignment, including fractional display
  scaling.
- Visual mask/outline appearance on real light, dark, and busy screenshots.

## Fixes after desktop testing

- The overlay now normalizes each worker mask into canonical alpha coverage
  before painting, so both true-alpha masks and legacy opaque grayscale masks
  reveal only the subject instead of tinting the whole frozen display.
- Object selection keeps the frozen screenshot as the base image, dims only the area
  outside the subject, and draws the selected subject with a contrast outline so
  it reads as popped out.
- The interaction model is click or lasso -> subject pops out -> nearby action
  chip with Copy image, Save PNG, and X to remove the selection. Removing keeps
  the overlay active so the user can immediately select another object.
- Edge-touching and multi-piece notes are shown in the action chip text, not by
  colour alone.

## Quality fixes after desktop testing

- Click prompts now choose a larger near-tied EfficientSAM multimask candidate
  when it still contains the foreground point, then run one padded box
  refinement pass. On the Google Images apple regression fixture, iStock click
  vs lasso IoU improved from `0.372` to `0.985`.
- Postprocessing removes tiny components, fills holes up to `96` px, trims
  uniform bright/dark backdrop leakage from mask edges, and constrains lasso
  masks to the drawn polygon with a small margin. The wordmark lasso area fell
  from `0.0061` to `0.0008` of the screenshot.
- Follow-up artifact review found UI-card container over-selection. Point
  selection now rejects near-rectangular container candidates in favor of the
  inner object under the click, and refinement is rejected when it turns a clean
  object mask into a filled card/container. Lasso prompts around card objects
  use the lasso centroid color to trim uniform card background.
- The local Google Images regression now has object-only click cutouts for the
  iStock apple, grid apple, Apple logo, and Google wordmark. Remaining visible
  weakness: the grid-apple lasso is object-sized but still clips the apple and
  can retain a small in-image licence badge fragment.
- Round-2 worker follow-up removed the hard polygon clip: lasso prompts are now
  treated as ROI seeds and candidate object masks are kept whole when their
  majority lies inside the loop. New overlay-state screenshots were saved as
  ignored local fixtures, but because they already contain painted mask pixels,
  they are noted as diagnostic screenshots rather than clean segmentation
  source images.
- Mask files are now true private RGBA alpha PNGs: white RGB and alpha equal to
  the binary mask, instead of opaque grayscale PNGs.
- Local regression fixture:
  `worker/benchmarks/segmentation/fixtures/real/google-images-apple-user-regression.jpg`
  is user-provided, ignored, and documented as local-only; review artifacts are
  generated under `/tmp/kiriglyph-quality/`.
