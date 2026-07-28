# Ubuntu Live Text and Subject Lift V0

Status: in-progress

Ordered delivery and dependencies: [Development V0 roadmap](roadmap.md).

## Problem Statement

Ubuntu users cannot select text directly from arbitrary images or paused video
frames displayed by existing applications. They also lack a local,
system-integrated way to click or draw around a visible subject and export it
without its background. Current Linux tools do not prove the spatial,
character-accurate interaction needed for a native-feeling Live Text and
Subject Lift experience.

The first development version must validate both capabilities locally without
prematurely building the hardened architecture, packaging, or operating-system
integration required for a production release. Text is the first exit gate;
subject lifting follows as a separate V0 milestone.

## Solution

Build a Linux desktop prototype with Flutter and Python. A user opens or
captures an image, the Flutter application sends it to long-lived local
workers, and receives engine-neutral OCR geometry or a subject mask. Flutter
lets the user drag across exact character ranges, copy recognized text, click
or draw around a subject, refine its mask, and export a transparent PNG.

After this image-file vertical slice works, add GNOME Wayland capture through the XDG Screenshot portal. A paused video is handled by capturing its visible frame rather than reading the video file.

All OCR and segmentation remain inside the local processing boundary. Pixels,
recognized text, embeddings, and masks exist only for the active capture
session.

## User Stories

1. As an Ubuntu user, I want to open an image and recognize its text locally, so that I can extract text without uploading private content.
2. As an Ubuntu user, I want to see recognized lines in their positions on the image, so that I understand which visual content produced each result.
3. As an Ubuntu user, I want to drag across exact character ranges directly on
   an image, including partial words and multiple lines, so that the image
   behaves like selectable text.
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
16. As an Ubuntu user, I want to click a visible subject or draw around it, so
    that I can isolate it from the background.
17. As an Ubuntu user, I want to copy or save the isolated subject as a
    transparent PNG, so that I can reuse it in another application.
18. As a privacy-conscious user, I want segmentation to run locally without an
    LLM or remote model service.

## Implementation Decisions

- Flutter owns all V0 user interface, application state, result rendering, selection, clipboard actions, and user-visible errors.
- The result surface is a normal desktop window. A transparent, click-through, or compositor-level fullscreen overlay is not part of V0.
- The capture surface is rendered with validated character-range geometry
  above it and a synchronized standard selectable text representation beside
  or below it.
- Riverpod manages capture-session and worker state; process and OCR details remain outside widgets.
- Python 3.12 hosts the OCR worker.
- Flutter launches one long-lived Python child process with `Process.start`.
- The process interface is versioned newline-delimited JSON over stdin and stdout. Each request and response has a request ID.
- Standard output contains protocol messages only. Diagnostics go to standard error and exclude captured pixels and recognized text.
- The OCR boundary returns ordered lines and validated character ranges in
  source-image coordinates, with provenance, confidence, timings, and typed
  errors.
- RapidOCR with ONNX Runtime CPU is the first adapter. The result contract does not expose RapidOCR-specific types.
- Character geometry must be measured rather than approximated by evenly
  dividing line or word rectangles. If RapidOCR cannot satisfy the fixture
  thresholds, V0 evaluates another local OCR adapter before implementing drag
  selection.
- Image dragging supports partial words, punctuation, whitespace, and
  multiline ranges. A standard selectable text panel remains the accessible
  fallback.
- Subject Lift is a separate V0 milestone after the Text acceptance gate. It
  uses a local interactive segmentation adapter selected through a bounded
  CPU/quality bake-off.
- Subject selection accepts point and drawn-region prompts and produces a
  validated mask. V0 exports a transparent PNG and image clipboard payload.
- Subject lifting does not imply semantic identification; naming an object is
  outside V0 unless separately approved.
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
- OCR adapter tests use small, non-sensitive fixtures and assert text,
  character-range ordering, containment, polygon bounds, and invariant
  validity rather than exact confidence values.
- Character-drag tests cover partial words, punctuation, whitespace,
  multiline ranges, rotation, perspective, zoom, and invalid-geometry fallback.
- Segmentation tests use non-sensitive fixtures and measure mask validity,
  prompt consistency, boundary quality, cancellation, and transparent export.
- Flutter state tests exercise capture-session transitions, stale response
  rejection, character selection, mask selection, copy/export construction,
  retry, cancellation, and worker failure.
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
- Offline translation or data detectors
- Persistent OCR history
- Cloud OCR, remote inference, LLMs, or generative models
- Production process isolation
- Flatpak, Snap, Debian, or AppImage packaging
- Autostart, background capture, or automatic shortcut modification
- Cross-platform release parity
- Final production OCR-engine selection
- Ubuntu or GNOME upstream integration
- Semantic object naming, classification, or Visual Look Up knowledge results
- Automatic background removal without explicit user action
- Production segmentation-model selection or GPU-specific acceleration

## Further Notes

- Development and capture acceptance must use an Ubuntu on Wayland session; the initial machine inspection found the current session running X11.
- RapidOCR is a development adapter, not the production winner. The existing three-engine bake-off remains the basis for a later production decision.
- If Flutter accessibility, Wayland behavior, latency, or process reliability fails the V0 acceptance evidence, the production architecture may reopen the native-service research without rewriting the engine-neutral result contract.
