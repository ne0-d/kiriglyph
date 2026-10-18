# Worker protocol goldens

One NDJSON reply per file, produced by the worker's own protocol
functions (`worker/src/worker/protocol.py`, `segmentation_protocol.py`,
and `segmentation_contract.py`). Recognize success regions come from
RapidOCR on a generated image. `timings_ms.total` on that reply is
pinned to `0.0` because the clock is not part of the contract.
`masks/prompt-ok.png` is the file named by the prompt reply.

The OCR worker has no ping method. Supported methods are `recognize`
and `decode_codes`, so there is no ping-ok reply to record.

Regenerate from the repository root:

```
PYTHONPATH=src worker/.venv/bin/python worker/tests/regenerate_golden.py
```

`worker/tests/test_golden_protocol.py` fails when a checked-in file
differs from that fresh output. A protocol change has to update the
goldens in the same change.
