# Live Text worker

Long-lived Python 3.12 process that speaks versioned NDJSON on stdin/stdout.

Runtime dependencies: Python standard library only.

## Protocol (v1)

Request:

```json
{"version":1,"id":"<id>","method":"recognize","params":{"image_path":"<absolute path>"}}
```

Success:

```json
{"version":1,"id":"<id>","ok":true,"result":{"image":{"width":64,"height":32},"full_text":"Mock recognized text","regions":[{"id":"line-1","level":"line","text":"Mock recognized text","polygon":[[8,8],[56,8],[56,24],[8,24]],"confidence":1.0,"reading_order":0}],"timings_ms":{"total":0}}}
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
