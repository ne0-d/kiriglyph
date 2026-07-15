# Evaluate local OCR engines

Type: research
Status: resolved
Blocked by:

## Question

Which actively maintained, redistributable local OCR stack best fits English-first spatial text recognition on Ubuntu CPU hardware while preserving word or line geometry, reading order, confidence, rotation handling, and a multilingual extension path? Compare at least Tesseract, PaddleOCR, and viable ONNX-based alternatives using primary documentation, source repositories, model licenses, runtime footprint, packaging constraints, and published or reproducible accuracy and latency evidence.

## Answer

Run a pinned Ubuntu CPU bake-off of Tesseract 5.5.3 with
`tessdata_fast/eng`, PaddleOCR 3.7.0 with PP-OCRv6 small, and RapidOCR
3.10.0 with ONNX Runtime 1.31.0 and PP-OCRv6 small. Treat a direct ONNX
Runtime C/C++ port as a bounded deployment spike, not a fourth accuracy
candidate, and do not declare a winner before testing one held-out local
screenshot/scene corpus.

Blockers are Python-free PP-OCRv6 feasibility, semantic reading order,
clickable word geometry (including open RapidOCR word-box defects), confidence
calibration, rotation parity, redistribution/SBOM closure, and missing
latency, RAM, package-size, and quality gates.

See the [research report](../research/02-local-ocr-engine.md).
