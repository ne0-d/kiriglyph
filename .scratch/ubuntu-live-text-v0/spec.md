# Kiriglyph V0: selection overlay for text and subjects

Status: in-progress

Ordered delivery and dependencies: [Development V0 roadmap](roadmap.md).

"Live Text" here means the **selection overlay**: press a shortcut and the
screen in front of you becomes selectable, like Circle to Search. It covers
selecting and copying text and lifting a subject out of its background. There
is no manual open-an-image workflow.

## Problem Statement

Ubuntu users cannot select text directly from arbitrary images, web pages, or
paused video frames displayed by existing applications. They also lack a local,
system-integrated way to click or draw around a visible subject and export it
without its background. Current Linux tools do not prove the spatial,
character-accurate interaction needed for a native-feeling Live Text and
Subject Lift experience.

The first development version must validate both capabilities locally, inside
the overlay, without prematurely building the hardened architecture, packaging,
or operating-system integration required for a production release. Text is the
first exit gate; Subject Lift follows as a separate V0 milestone in the same
overlay.

## Solution

Build a Linux desktop prototype with Flutter and Python. A GNOME shortcut wakes
the already-running app, which takes a silent full-screen capture through the
XDG Screenshot portal and covers only the display under the pointer with a
borderless fullscreen view of that display's frozen pixels. The desktop appears
unchanged; a brief edge glow signals selection mode while local workers run.

In **Text** mode the user drags across characters, double-clicks a word,
triple-clicks a paragraph, or draws a circle that snaps to whole paragraphs,
then copies the text. In **Subject** mode the user clicks or draws around a
visible subject, refines its mask, and copies or saves it as a transparent PNG.
If OCR finds no text, the overlay stays open, explains that no text was found,
and keeps object selection available for photos, image viewers, and paused frames
without visible subtitles.
Escape, Close, or focusing another display returns to the live desktop. A paused
video is handled by capturing its visible frame rather than reading the video
file.

A small normal window exists only for setup: the one-time instant-capture
permission, GNOME shortcut instructions, and status.

All OCR and segmentation remain inside the local processing boundary. Pixels,
recognized text, embeddings, and masks exist only for the active capture
session.

## User Stories

1. As an Ubuntu Wayland user, I want a shortcut to freeze the display I'm using in place and make its text selectable, so that it feels like the desktop itself became selectable rather than another app opening.
2. As a user with several displays, I want only the display under my pointer to freeze, so that my other displays stay live and usable.
3. As an Ubuntu user, I want to drag across exact character ranges directly on the frozen screen, including partial words and multiple lines, so that the screen behaves like selectable text.
4. As a user, I want double-click to select a word and triple-click to select a paragraph, so that common selections are fast.
5. As a user, I want to draw a rough circle and get the whole paragraphs it covers, so that I don't need precise dragging.
6. As a user, I want selections to look like normal document text selection, one continuous band per line including spaces, so that selecting feels smooth rather than tiled.
7. As a user, I want to copy the selection, or all recognized text, so that I can reuse it quickly.
8. As a keyboard user, I want to navigate, select, copy, and dismiss without a pointer, so that the core workflow is keyboard operable.
9. As a user of assistive technology, I want recognized text and status exposed through standard Flutter semantics, so that they are not available only as painted geometry.
10. As a video viewer, I want to pause a video and capture its visible text, so that the workflow does not depend on the video player.
11. As a privacy-conscious user, I want captures, OCR text, and masks discarded when I dismiss the overlay, so that the application does not build a history.
12. As a user, I want to grant screen access once, explicitly, so that later shortcut captures are instant and silent.
13. As a user, I want cancellation and dismissal treated as normal, so that backing out never produces an alarming error.
14. As a user, I want failures to distinguish capture, OCR timeout, worker, and clipboard problems, and I want successful no-text OCR to keep object selection available, so that I know what action to take.
15. As an Ubuntu user, I want to click a visible subject or draw around it, so that I can isolate it from the background.
16. As an Ubuntu user, I want to copy or save the isolated subject as a transparent PNG, so that I can reuse it in another application.
17. As a privacy-conscious user, I want segmentation to run locally without an LLM or remote model service.
18. As a developer, I want OCR engines hidden behind one result contract, so that RapidOCR can later be compared with Tesseract or PaddleOCR without rewriting the Flutter UI.
19. As a developer, I want deterministic image fixtures and schema validation, so that changes to OCR integration cannot silently break geometry or protocol compatibility.
20. As a developer, I want one command to bootstrap, install, and run both parts, so that contributors can reproduce the V0 environment.

## Implementation Decisions

- Flutter owns all V0 user interface, application state, result rendering, selection, clipboard actions, and user-visible errors.
- The primary and only result surface is a borderless fullscreen selection overlay on the display under the pointer, showing that display's frozen pixels at exact physical size. Other displays stay live; focusing them dismisses the overlay.
- The normal window is a setup surface only: instant-capture permission, shortcut steps, status, and quit. V0 has no "open image" workflow and no image-file picker for input.
- The overlay shows no region or character outlines by default. Selection renders as one continuous highlight band per line, following the line's tilt, including spaces. The pointer is a text cursor over text.
- A drag that starts on text selects characters; a drag that starts off text is classified as either a text loop or an object lasso. Paragraphs are grouped from line spacing, text height, alignment, and horizontal overlap.
- Text and Subject are explicit modes of the overlay, so pointer behaviour is never ambiguous.
- Flutter UI uses the `yaru` package for Ubuntu-native theme and controls.
- Riverpod manages capture-session and worker state; process and OCR details remain outside widgets.
- Python 3.12+ hosts the OCR worker.
- Flutter launches one long-lived Python child process with `Process.start`.
- The process interface is versioned newline-delimited JSON over stdin and stdout. Each request and response has a request ID.
- Standard output contains protocol messages only. Diagnostics go to standard error and exclude captured pixels and recognized text.
- The OCR boundary returns ordered lines and validated character ranges in source-image coordinates, with provenance, confidence, timings, and typed errors.
- RapidOCR with ONNX Runtime CPU is the first adapter. The result contract does not expose RapidOCR-specific types.
- Character geometry must be measured rather than approximated by evenly dividing line or word rectangles.
- Subject Lift uses a local interactive segmentation adapter selected through a bounded CPU/quality bake-off. It accepts point and drawn-region prompts, computes one embedding per capture, and produces a validated mask. Export is a transparent PNG and an image clipboard payload from the overlay toolbar. It does not imply semantic identification.
- Screen capture uses Python `dbus-fast` (the maintained fork of `dbus-next`) in a one-shot helper process calling the XDG Screenshot portal with `interactive=false`. GNOME returns one image spanning all displays; the app crops the active display using the monitor layout.
- Silent capture requires a one-time GNOME access dialog, which GNOME only shows to the focused app. The setup window's "Enable instant capture" action triggers it. The app has a real application ID and installed desktop file so GNOME stores the grant against it.
- A silent capture writes `~/Pictures/Screenshot*.png` without clipboard, notification, or Screenshots-folder side effects. The app reads it into memory and deletes exactly the returned file immediately; it never deletes any other file. GNOME plays its screenshot flash and sound on every capture; this is accepted.
- The app autostarts hidden at login and stays resident with a warm OCR worker. A GNOME custom shortcut runs the app's selection command, which activates the resident single instance; repeated activation never opens a second overlay or worker. The app never modifies GNOME settings itself.
- Flutter dependencies are locked with the pub lockfile. Python dependencies use `pyproject.toml` and a `uv` lockfile.
- Shared JSON schemas define protocol envelopes and OCR result structures.
- Captured content, OCR results, embeddings, and masks remain in memory for one capture session. Persistent history, content telemetry, and notification previews are absent. The only on-disk copy is a private owner-only crop under `$XDG_RUNTIME_DIR` for the OCR worker, deleted when the session ends.
- Developer bootstrap and install scripts are the only V0 distribution mechanism.

## Testing Decisions

- The primary seam is the versioned Flutter-to-Python worker contract. Fixed image fixtures must produce schema-valid OCR results that Flutter can render without knowing the OCR engine.
- Worker contract tests exercise startup, request correlation, malformed messages, no-text results, OCR failure, timeout, cancellation by worker restart, and graceful shutdown.
- OCR adapter tests use small, non-sensitive fixtures and assert text, character-range ordering, containment, polygon bounds, and invariant validity rather than exact confidence values.
- Character-drag, circle, and paragraph tests cover partial words, punctuation, whitespace, multiline ranges, rotation, perspective, zoom, paragraph grouping, and invalid-geometry fallback.
- Segmentation tests use non-sensitive fixtures and measure mask validity, prompt consistency, boundary quality, cancellation, and transparent export.
- Flutter state tests exercise capture-session transitions, stale response rejection, character selection, mask selection, copy/export construction, retry, cancellation, and worker failure.
- Portal tests cover success, permission denied, unavailable portal, invalid URI, and deletion of the returned file.
- Display-crop tests use synthetic multi-display layouts, including mixed resolutions and fractional scales.
- Wayland acceptance tests run manually on Ubuntu 26.04 GNOME 50 Wayland for the overlay flow, with one and two displays and fractional scaling. X11-only success is not sufficient.
- Tests assert that protocol logs and normal diagnostics do not contain recognized text or image data.
- External behavior is tested through module interfaces; implementation details of RapidOCR, Riverpod providers, or JSON parsing are not asserted directly.

## Out of Scope

- Rust or C++ services
- A custom GTK result surface
- A transparent or click-through overlay over live applications, or a GNOME Shell extension
- Overlays on more than one display at once
- A manual "open an image file" workflow
- Continuous video OCR or frame tracking
- Reading video files directly
- Offline translation or data detectors
- Persistent OCR history
- Cloud OCR, remote inference, LLMs, or generative models
- Production process isolation
- Flatpak, Snap, Debian, or AppImage packaging
- Capture without an explicit shortcut press, or automatic shortcut modification
- Cross-platform release parity
- Final production OCR-engine selection
- Ubuntu or GNOME upstream integration
- Semantic object naming, classification, or Visual Look Up knowledge results
- Automatic background removal without explicit user action
- Production segmentation-model selection or GPU-specific acceleration

## Further Notes

- Development and capture acceptance use Ubuntu 26.04 GNOME 50 on Wayland.
- Overlay direction and silent-capture evidence: [ADR 0001](../../docs/adr/0001-selection-overlay-silent-capture.md).
- RapidOCR is a development adapter, not the production winner. The existing three-engine bake-off remains the basis for a later production decision.
- If Flutter accessibility, Wayland behavior, latency, or process reliability fails the V0 acceptance evidence, the production architecture may reopen the native-service research without rewriting the engine-neutral result contract.
