# Live Text worker

Long-lived Python 3.12 process that speaks versioned NDJSON on stdin/stdout.

Recognition uses pinned RapidOCR and ONNX Runtime CPU dependencies. RapidOCR's
default detector, classifier, and recognizer models are contained in its wheel;
OCR requests do not download models.

## Protocol (v1)

Request:

```json
{"version":1,"id":"<id>","method":"recognize","params":{"image_path":"<absolute path>"}}
```

Success:

```json
{"version":1,"id":"<id>","ok":true,"result":{"image":{"width":1000,"height":260},"full_text":"HELLO","regions":[{"id":"line-1","level":"line","text":"HELLO","polygon":[[38,57],[387,57],[387,181],[38,181]],"confidence":0.99,"reading_order":0}],"timings_ms":{"total":1200}}}
```

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

## Development

```bash
cd worker
../.tools/uv-bin/uv sync --locked --group dev
../.tools/uv-bin/uv run --locked pytest -v
```
