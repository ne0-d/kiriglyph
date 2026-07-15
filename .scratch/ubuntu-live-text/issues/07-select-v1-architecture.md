# Select the development V0 architecture and stack

Type: grilling
Status: resolved
Blocked by: 01, 02, 03, 04

## Question

Which minimal architecture proves the approved capture-to-selection experience without prematurely adopting the hardened production architecture?

## Answer

Development V0 uses **Flutter and Python**. It proves the product interaction before production hardening.

### Flutter application

- Owns the Linux desktop UI, capture command, result surface, selection state, copy actions, and user-visible errors.
- Uses a normal application window rather than a custom fullscreen or transparent overlay.
- Starts and supervises the local Python worker.
- Keeps OCR results in memory only for the active capture session.

### Python worker

- Runs as one long-lived child process during development.
- Communicates with Flutter through newline-delimited JSON over stdin/stdout.
- Uses request IDs so responses can be matched to asynchronous Flutter operations.
- Accepts image paths and returns engine-neutral lines, words, polygons, confidence, reading order, timings, and typed errors.
- Writes diagnostics only to stderr and never logs captured pixels or recognized text.
- Starts with a RapidOCR/ONNX Runtime adapter because it is local, Python-friendly, CPU-capable, and returns spatial polygons. The adapter remains replaceable; Tesseract and PaddleOCR stay available for the later bake-off.
- Guarantees line-level geometry first. Word-level selection is added only after fixture tests validate the engine's derived word geometry.

### Capture path

- Use the XDG Screenshot portal on GNOME Wayland.
- Prove opening an existing image before portal integration so the OCR bridge and spatial result surface can be tested independently.
- A user-configured GNOME shortcut and single-instance activation are later V0 slices, not prerequisites for the first image-to-text slice.

### Dependencies and distribution

- Pin Flutter dependencies with the standard pub lockfile.
- Manage Python 3.12 dependencies with `pyproject.toml` and a `uv` lockfile.
- Keep the NDJSON contract versioned and validate it against shared JSON schemas and fixed, non-sensitive image fixtures.
- Provide developer bootstrap and launch scripts only. Packaging and installers begin after the V0 workflow is proven.

### Deferred from V0

- Rust or C++ services, a custom GTK result surface, D-Bus service APIs, OCR worker isolation, production installers, Flatpak sandbox hardening, autostart, and upstream integration.
- Reassess these only after V0 supplies measured OCR quality, latency, memory, accessibility, and Wayland behavior.
