# 02: Recognize a local image with RapidOCR

**What to build:** A user can choose a local image and receive real, fully local RapidOCR line recognition with ordered text and spatial polygons rendered by the existing Flutter result surface.

**Blocked by:** 01: Run a mock OCR result end to end.

**Status:** ready-for-agent

- [ ] The Python worker loads RapidOCR with ONNX Runtime CPU once and reuses it across requests.
- [ ] Model assets are provisioned during development setup and no OCR request downloads code or models.
- [ ] OCR responses remain engine-neutral and include ordered lines, source-image polygons, confidence, and timings.
- [ ] Empty, unreadable, unsupported, and malformed image inputs return typed outcomes without terminating the worker.
- [ ] Fixture tests assert transcript, ordering, polygon bounds, and schema validity without relying on exact confidence values.
- [ ] Flutter renders real line results without importing or interpreting RapidOCR-specific types.
