# Ubuntu Live Text V0

Status: ready-for-agent

## Problem Statement

Ubuntu users cannot select text directly from arbitrary images or paused video frames displayed by existing applications. Current Linux OCR tools generally copy an entire OCR result and do not prove the spatial selection workflow needed for a native-feeling Live Text experience.

The first development version must validate that workflow quickly and locally without prematurely building the hardened architecture, packaging, or operating-system integration required for a production release.

## Solution

Build a Linux desktop prototype with Flutter and Python. A user opens an image, the Flutter application sends its path to a long-lived local Python worker, and the worker returns an engine-neutral OCR result containing ordered text regions and spatial polygons. Flutter displays those regions over the capture surface, lets the user select lines and copy their text, and provides synchronized selectable plain text.

After this image-file vertical slice works, add GNOME Wayland capture through the XDG Screenshot portal. A paused video is handled by capturing its visible frame rather than reading the video file.

All recognition remains inside the local processing boundary. Pixels and recognized text exist only for the active capture session.

## User Stories

1. As an Ubuntu user, I want to open an image and recognize its text locally, so that I can extract text without uploading private content.
2. As an Ubuntu user, I want to see recognized lines in their positions on the image, so that I understand which visual content produced each result.
3. As an Ubuntu user, I want to select one or more text regions, so that I can copy only the content I need.
4. As an Ubuntu user, I want to copy all recognized text, so that I can quickly reuse the complete result.
5. As an Ubuntu user, I want a synchronized selectable text view, so that I can make character-level selections even when image-region geometry is only line-accurate.
6. As a keyboard user, I want to navigate recognized regions and copy or dismiss the result without a pointer, so that the core workflow is keyboard operable.
7. As a user of assistive technology, I want recognized text exposed through standard Flutter semantics, so that it is not available only as painted boxes.
8. As an Ubuntu Wayland user, I want to capture an area, window, or screen through GNOME's trusted selector, so that screen access is explicit and compositor mediated.
9. As a video viewer, I want to pause a video and capture its visible text, so that the OCR workflow does not depend on the video player.
10. As a privacy-conscious user, I want captures and OCR text discarded when I close the result, so that the application does not build a history.
11. As a user, I want cancellation treated as normal, so that backing out does not produce an alarming error.
12. As a user, I want failures to distinguish capture, OCR, no-text, timeout, worker, and clipboard problems, so that I know what action to take.
13. As a developer, I want OCR engines hidden behind one result contract, so that RapidOCR can later be compared with Tesseract or PaddleOCR without rewriting the Flutter UI.
14. As a developer, I want deterministic image fixtures and schema validation, so that changes to OCR integration cannot silently break geometry or protocol compatibility.
15. As a developer, I want one command to bootstrap and run both parts during development, so that contributors can reproduce the V0 environment.

## Implementation Decisions

- Flutter owns all V0 user interface, application state, result rendering, selection, clipboard actions, and user-visible errors.
- The result surface is a normal desktop window. A transparent, click-through, or compositor-level fullscreen overlay is not part of V0.
- The capture surface is rendered with spatial text regions above it and a synchronized standard selectable text representation beside or below it.
- Riverpod manages capture-session and worker state; process and OCR details remain outside widgets.
- Python 3.12 hosts the OCR worker.
- Flutter launches one long-lived Python child process with `Process.start`.
- The process interface is versioned newline-delimited JSON over stdin and stdout. Each request and response has a request ID.
- Standard output contains protocol messages only. Diagnostics go to standard error and exclude captured pixels and recognized text.
- The worker accepts an image path and returns an engine-neutral OCR result containing ordered lines, optional words, polygons in source-image coordinates, confidence, timings, and typed errors.
- RapidOCR with ONNX Runtime CPU is the first adapter. The result contract does not expose RapidOCR-specific types.
- Line selection is required first. Word selection is enabled only after fixture tests validate word splitting and geometry.
- The first vertical slice uses an existing image selected through Flutter's file selector.
- A later V0 slice uses Python `dbus-next` to call the XDG Screenshot portal on GNOME Wayland.
- User-configured GNOME shortcut activation follows portal capture and is not required for the first usable demo.
- Flutter dependencies are locked with the pub lockfile. Python dependencies use `pyproject.toml` and a `uv` lockfile.
- Shared JSON schemas define protocol envelopes and OCR result structures.
- Captured content and OCR results remain in memory for one capture session. Persistent history, content telemetry, and notification previews are absent.
- Developer bootstrap and launch scripts are the only V0 distribution mechanism.

## Testing Decisions

- The primary seam is the versioned Flutter-to-Python worker contract. Fixed image fixtures must produce schema-valid OCR results that Flutter can render without knowing the OCR engine.
- Worker contract tests exercise startup, request correlation, malformed messages, no-text results, OCR failure, timeout, cancellation by worker restart, and graceful shutdown.
- OCR adapter tests use small, non-sensitive fixtures and assert text, ordering, polygon bounds, and invariant validity rather than exact confidence values.
- Flutter state tests exercise capture-session transitions, stale response rejection, selection, copy text construction, retry, cancellation, and worker failure.
- Flutter widget tests verify that an OCR result creates visible spatial regions and synchronized selectable text.
- Portal tests cover success, user cancellation, unavailable portal, invalid URI, and cleanup. They run separately from the image-file contract tests.
- Wayland acceptance tests run manually on Ubuntu 24.04 GNOME Wayland for the capture flow. X11-only success is not sufficient.
- Tests assert that protocol logs and normal diagnostics do not contain recognized text or image data.
- External behavior is tested through module interfaces; implementation details of RapidOCR, Riverpod providers, or JSON parsing are not asserted directly.

## Out of Scope

- Rust or C++ services
- A custom GTK result surface
- A transparent, click-through, persistent, or compositor-level overlay
- Continuous video OCR or frame tracking
- Reading video files directly
- Character-accurate image-overlay selection
- Offline translation or data detectors
- Persistent OCR history
- Cloud OCR, remote inference, LLMs, or generative models
- Production process isolation
- Flatpak, Snap, Debian, or AppImage packaging
- Autostart, background capture, or automatic shortcut modification
- Cross-platform release parity
- Final production OCR-engine selection
- Ubuntu or GNOME upstream integration

## Further Notes

- Development and capture acceptance must use an Ubuntu on Wayland session; the initial machine inspection found the current session running X11.
- RapidOCR is a development adapter, not the production winner. The existing three-engine bake-off remains the basis for a later production decision.
- If Flutter accessibility, Wayland behavior, latency, or process reliability fails the V0 acceptance evidence, the production architecture may reopen the native-service research without rewriting the engine-neutral result contract.
