# Kiriglyph worker

Long-lived Python 3.12+ process that speaks versioned NDJSON on stdin/stdout.

Recognition uses pinned RapidOCR and ONNX Runtime CPU dependencies. RapidOCR's
default detector, classifier, and recognizer models are contained in its wheel;
OCR requests do not download models.

Subject segmentation runs in a separate on-demand worker process because
EfficientSAM-Ti uses about 1.3 GiB RSS while loaded. The app starts it for an
overlay session and kills or closes it when the session ends, so embeddings and
mask files are process/session-local.

## Protocol (v1)

Request:

```json
{"version":1,"id":"<id>","method":"recognize","params":{"image_path":"<absolute path>"}}
```

Success:

```json
{"version":1,"id":"<id>","ok":true,"result":{"image":{"width":1000,"height":260},"full_text":"HELLO","regions":[{"id":"line-1","level":"line","text":"HELLO","polygon":[[38,57],[387,57],[387,181],[38,181]],"confidence":0.99,"reading_order":0,"ranges":[]}],"timings_ms":{"total":1200}}}
```

Each line has a `ranges` array. Valid character geometry uses contiguous
half-open code-point offsets and provenance `derived_ctc_polygon`; logical
spaces use `interpolated_gap`. An empty array preserves line-level selection
when precise geometry is unavailable.

Error:

```json
{"version":1,"id":"<id-or-null>","ok":false,"error":{"code":"malformed_json","message":"..."}}
```

Stdout carries protocol messages only. Diagnostics go to stderr and must not include recognized text.

The worker accepts NDJSON request lines up to 1 MiB. Larger lines return a
typed `malformed_json` response and the worker drains the rest of the line
before reading the next request. Image dimension probing reads bounded file
headers only; JPEG marker scanning is capped at 1 MiB before returning
`image_unreadable`.

## Screen capture helper

`python -m worker.portal_capture` (or `kiriglyph-capture`) is a separate
one-shot process. It asks the XDG Screenshot portal for an interactive capture,
waits for the user to choose an area, window, or screen, and prints exactly one
JSON line:

```json
{"outcome":"captured","path":"/home/me/Pictures/Screenshots/Screenshot.png"}
```

Other outcomes are `cancelled`, `ended`, `unavailable`, `denied`, `failed`,
`invalid_uri`, and `unreadable`. GNOME owns an interactive capture's file.
Diagnostics on stderr never include paths or URIs.

Flags:

- `--silent` requests a non-interactive capture of all displays. Without a
  stored grant it returns `ended` at once. The file it writes to `~/Pictures`
  belongs to the caller, which must delete exactly that path after reading it.
- `--app-id <id>` first calls `org.freedesktop.host.portal.Registry.Register`
  on the helper's own connection, so the grant is stored against that ID. It
  needs `~/.local/share/applications/<id>.desktop`. A registration failure
  returns `unavailable`.

## Subject segmentation

Install model files explicitly before using Subject mode:

```bash
cd worker
../.tools/uv-bin/uv run --locked kiriglyph-fetch-models
```

The command downloads the two official Apache-2.0 EfficientSAM-Ti ONNX files,
checks pinned SHA-256 digests, writes them atomically, and is idempotent. At
runtime no network access is used. Model files live under
`$XDG_DATA_HOME/kiriglyph/models/efficientsam-ti/` by default. Set
`KIRIGLYPH_MODELS_DIR` to override the models root; for tests it may either be
the root containing `efficientsam-ti/` or the model directory itself.

Run the process with:

```bash
python -m worker.segmentation_worker
```

Protocol v1 uses newline-delimited JSON on stdin/stdout and keeps masks out of
the 1 MiB line cap by writing private `0600` alpha PNG files under
`$XDG_RUNTIME_DIR`. Mask files are RGBA PNGs: RGB is always white
(`255,255,255`) and alpha is the binary subject mask (`0` or `255`).

| Method | Params | Success result |
| --- | --- | --- |
| `embed` | `{"source":"path","image_path":"/private/crop.png"}` or PNG bytes | Opaque handle, source image size, load/embed timings |
| `prompt` | `handle` plus foreground/background points, optional box, optional polygon | Mask file reference, outcome/statistics, bounds, confidence, timings |
| `cancel` | `{"request_id":"embed-1"}` | Acknowledges cancellation; if ORT is already running, the worker discards the eventual result and replies `cancelled` for the original request |
| `close` | `{}` | Closes the session, deletes mask files, and exits |

Polygon prompts use the loop only as a region of interest. The adapter runs the
decoder on a deterministic 4×4 grid plus one box prompt, rejects unstable,
background-like, rectangular, and duplicate candidates, then unions every
distinct mask whose majority lies inside the loop without clipping it to the
loop boundary.
Point-only prompts choose among EfficientSAM's multimask candidates by requiring
the foreground point and preferring a larger candidate when scores are near-tied,
then run one padded box refinement. Click cleanup removes tiny specks, fills only
small holes, and trims uniform bright/dark backdrop leaks. Lasso cleanup trims
those leaks and specks while preserving decoder holes and concavities.

Crop-only U2-Net (Apache-2.0) scored 0.738 overall / 0.765 multi-object IoU and 0.957 stability at 629 ms / 952 MiB RSS.
The SAM ROI path scored 0.838 overall / 0.781 multi-object IoU and 0.845 stability at 582 ms / 1,112 MiB RSS.
U2-Net was not adopted because it did not beat SAM on multi-object IoU despite its higher stability.

Mask outcomes are `ok`, `empty`, and `suspect_full_image`. An `ok` result may
still flag `touches_edge`, and any result reports component count plus the
largest component bounds; `multiple_components` is true when the count is above
one. Failures are `cancelled`, `timeout`, `malformed_output`,
`model_load_failed`, `model_missing`, `process_died`, `out_of_memory`, and
`session_closed`. `model_missing` includes the command
`kiriglyph-fetch-models` for the UI to show.

Diagnostics go to stderr and must not include image paths, prompt coordinates,
recognized text, or file contents. Mask files and embeddings are private to the
session and are deleted on `close`; the Dart client also deletes returned mask
paths when its segmenter closes.

## Development

```bash
cd worker
../.tools/uv-bin/uv sync --locked --group dev
../.tools/uv-bin/uv run --locked pytest -v
```
