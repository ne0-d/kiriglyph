# 12 Segmentation Backend Plan

## Design

Subject segmentation is served by `python -m worker.segmentation_worker`, a
separate on-demand process from the warm OCR worker. It loads EfficientSAM-Ti
inside that process, keeps one or more embedding handles for the overlay
session, writes mask PNGs to a private runtime directory, and deletes them on
close. Killing the process is the hard privacy/cancellation boundary.

The shipped adapter is model-neutral at the contract boundary. It accepts
foreground/background points, an optional box, and an optional polygon/lasso.
Polygons are lowered to the lasso bounding box plus deterministic inside
samples: centroid first, then up to three vertices sampled in lasso order.

## Protocol

| Request | Purpose | Response |
| --- | --- | --- |
| `embed` | Precompute image embedding from a private crop path or PNG bytes | `handle`, image dimensions, load/embed timings |
| `prompt` | Produce a mask for the complete prompt state | alpha PNG path, SHA-256, byte length, bounds, mask stats, confidence, timings |
| `cancel` | Mark an in-flight request result as unwanted | Acknowledges cancel; original request eventually returns `cancelled` if ORT was already running |
| `close` | End the session | Deletes masks, drops embeddings, exits |

The process uses the same v1 NDJSON envelope as OCR: `version`, `id`, `method`,
and `params`, with stdout reserved for protocol messages and stderr restricted
to redacted diagnostics.

Mask file encoding is precise: `alpha_png_file` points to a private `0600` RGBA
PNG with white RGB (`255,255,255`) and alpha equal to the binary mask (`0` or
`255`). The PNG is transport for mask alpha, not an opaque grayscale image.

The EfficientSAM-Ti adapter postprocesses masks before writing them: point
prompts select a near-tied larger multimask candidate and run one padded
box-refinement pass; all prompts remove tiny specks, fill only small holes, and
trim uniform bright/dark backdrop leakage; lasso masks are constrained to the
drawn polygon with a small margin.

## Outcomes And Failures

Mask outcomes: `ok`, `empty`, `suspect_full_image`.

Flags/statistics: area fraction, nullable bounds, edge-touch booleans, connected
component count, largest component bounds, and `multiple_components`.

Failures: `cancelled`, `timeout`, `malformed_output`, `model_load_failed`,
`model_missing`, `process_died`, `out_of_memory`, `session_closed`.

## Install And Offline Story

`kiriglyph-fetch-models` is the only network path. It downloads the two pinned
official EfficientSAM-Ti ONNX files, verifies SHA-256, writes atomically, and
is safe to rerun. Runtime workers never fetch. Default assets live in
`$XDG_DATA_HOME/kiriglyph/models/efficientsam-ti/`; `KIRIGLYPH_MODELS_DIR`
overrides the root or direct model directory for development and tests.

If files are missing, the worker returns `model_missing` with
`kiriglyph-fetch-models` so the UI can show a precise recovery step.
