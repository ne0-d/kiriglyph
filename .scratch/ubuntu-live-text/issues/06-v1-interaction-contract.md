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
- Present the returned capture in a lightweight Flutter result surface with spatial word and line regions.
- Provide synchronized standard selectable text for character-level selection and assistive technologies.
- Delegate multi-monitor and fractional-scale capture selection to GNOME in V1.

### Actions and keyboard behavior

- Support Copy Selection, Copy All, Retry, Cancel, and Dismiss.
- Tab and Shift+Tab navigate controls; arrows move among OCR regions; Shift+arrows extend region selection; Enter copies; Ctrl+A selects all; Ctrl+C copies; Escape dismisses.
- Data detectors, offline translation, continuous video recognition, and persistent history are outside the first alpha.

### Progress, errors, accessibility, and privacy

- Show delayed progress only when recognition is perceptibly slow and permit cancellation throughout.
- Treat user cancellation as a normal outcome.
- Distinguish portal unavailable or denied, capture failure, no text, OCR timeout or failure, and clipboard failure.
- Expose ordered text through standard GTK semantics for Orca, announce status without automatically speaking recognized content, and restore focus when the result surface closes.
- Keep pixels and recognized text only for the active capture session. Do not retain history, emit telemetry containing capture activity, show recognized text in notifications, or capture in the background.
