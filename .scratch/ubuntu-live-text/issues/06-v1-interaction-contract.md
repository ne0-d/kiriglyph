# Define the V1 interaction contract

Type: grilling
Status: resolved
Blocked by: 01, 05

## Question

What exact user journey and observable behavior define a successful V1 capture session, including invocation, source choice, frozen-frame behavior, OCR progress, spatial selection, copy actions, keyboard operation, cancellation, errors, privacy feedback, accessibility, multi-monitor handling, and the smallest useful set of data actions?

## Answer

V1 targets Ubuntu 24.04 GNOME Wayland and requires Wayland for capture and release acceptance testing.

### Capture and presentation

- Start a capture session from a user-configured GNOME shortcut or the in-app **Capture Text** action.
- Use GNOME's native selector for area, window, or screen capture. Open image files through the system file chooser.
- Treat a paused video as visible screen content; V1 does not inspect or decode video files.
- Present the returned capture in a lightweight result surface with exact
  character-range geometry and validated line fallbacks.
- Support direct character dragging on the image and provide synchronized
  standard selectable text for assistive technologies.
- Provide an explicit Subject mode where a user can click or draw around a
  visible subject, refine the local segmentation mask, and copy or save a
  transparent PNG.
- Delegate multi-monitor and fractional-scale capture selection to GNOME in V1.

### Actions and keyboard behavior

- Support Copy Selection, Copy All, Copy Image, Save PNG, Retry, Cancel, and
  Dismiss.
- Tab and Shift+Tab navigate controls; arrows move among OCR regions; Shift+arrows extend region selection; Enter copies; Ctrl+A selects all; Ctrl+C copies; Escape dismisses.
- Semantic object naming, data detectors, offline translation, continuous video
  recognition, and persistent history are outside the first alpha.

### Progress, errors, accessibility, and privacy

- Show delayed progress only when recognition is perceptibly slow and permit cancellation throughout.
- Treat user cancellation as a normal outcome.
- Distinguish portal unavailable or denied, capture failure, no text, OCR timeout or failure, and clipboard failure.
- Expose ordered text through standard GTK semantics for Orca, announce status without automatically speaking recognized content, and restore focus when the result surface closes.
- Keep pixels, recognized text, character geometry, image embeddings, and masks
  only for the active capture session. Do not retain history, emit telemetry
  containing capture activity, show recognized content in notifications, or
  capture in the background.
