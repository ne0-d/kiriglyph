# 02: Recognize a local image with RapidOCR

**What to build:** A user can choose a local image and receive real, fully local RapidOCR line recognition with ordered text and spatial polygons rendered by the existing Flutter result surface.

**Blocked by:** 01: Run a mock OCR result end to end.

**Status:** resolved

- [x] The Python worker loads RapidOCR with ONNX Runtime CPU once and reuses it across requests.
- [x] Model assets are provisioned during development setup and no OCR request downloads code or models.
- [x] OCR responses remain engine-neutral and include ordered lines, source-image polygons, confidence, and timings.
- [x] Empty, unreadable, unsupported, and malformed image inputs return typed outcomes without terminating the worker.
- [x] Fixture tests assert transcript, ordering, polygon bounds, and schema validity without relying on exact confidence values.
- [x] Flutter renders real line results without importing or interpreting RapidOCR-specific types.

## Answer

The mock engine was replaced with pinned RapidOCR and ONNX Runtime CPU
dependencies. One engine is created per long-lived worker, packaged models are
used without request-time network access, and output is normalized to the
existing engine-neutral line-region contract. Tests cover a fixed real-text
fixture, bounds, ordering, confidence invariants, model reuse, no-text,
unreadable input, OCR failure, schema validity, and content-safe diagnostics.
