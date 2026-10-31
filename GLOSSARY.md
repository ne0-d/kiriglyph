# Glossary

## Selection overlay

The borderless fullscreen window, shown on the display under the pointer, that presents a frozen frame and lets the user select text or an object on it. It is opened by `kiriglyph --select` and is the product's one interface; the normal window is only for setup.

## Capture session

One explicit user interaction: take a silent capture, freeze a display, recognize its text, and keep the result available until the user copies, saves, or dismisses the overlay. Dismissing discards the frame, the private image copy, and the recognized text.

## Frozen frame

The still picture of one display, cropped from the capture, that the overlay shows and every selection is made on. It replaces what older documents called the capture surface and result surface.

## Display

One monitor, as GNOME reports it in logical pixels, with its scale factor. The overlay opens on the display under the pointer; other displays stay live.

## Locating a display

Finding the display under the pointer before the overlay is shown, with a tiny transparent probe window that is not fullscreen. The overlay window then goes fullscreen once, on that display, with the frozen frame already rendered. See [ADR 0002](docs/adr/0002-overlay-maps-once-on-a-located-display.md).

## Preferences window

The normal Kiriglyph window: first-run setup and settings in one page (screen access, shortcut, save location, launch at login, pause). It is not the product; the selection overlay is.

## Resident app

The Kiriglyph process that starts hidden at login and stays running, so the shortcut only forwards a command to it. It keeps the OCR worker warm.

## Instant capture grant

The one-time permission, stored by GNOME against the app's ID, that lets the Screenshot portal capture without a dialog. It is requested from the focused setup window.

## Text region

A spatially bounded piece of recognized text on a frozen frame.

## OCR result

The recognized text regions, their spatial positions, reading order, confidence, and character ranges for one frozen frame.

## Spatial selection

A selection of one or more text regions through their positions on the frozen frame. Character-level selection belongs to the synchronized text representation rather than the image overlay.

## Object (subject)

Something on the frozen frame that is not text: a person, logo, or item. The user lifts it with a click or by drawing around it, and a segmentation model returns a mask.

## Mask

A per-pixel alpha image that marks which pixels belong to the selected object. Exporting an object composes the source pixels with the mask into a transparent PNG.

## Outcome chip

A button shown beside a selection for each thing that can be done with it: Copy text, Lift object, Copy screenshot, Save screenshot, Open link, and so on. Which chips appear follows the outcome rules for the selection.

## Worker

A separate local process that does heavy work for the app over versioned NDJSON: the OCR worker (recognition and code decoding), the segmentation worker (object masks), and the one-shot screenshot portal helper.

## Local processing boundary

The privacy boundary under which captured pixels and recognized text remain on the user's device and are never sent to a remote service. The only data that leaves is something the user clicks, such as a web search of the selected text.
