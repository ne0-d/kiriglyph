# Glossary

## System-wide OCR overlay

A user-invoked interaction layer that makes text in visible on-screen content selectable, regardless of which application displays that content.

## Capture session

One explicit user interaction that takes a visual snapshot, recognizes its text, and keeps the result available until the user copies text or dismisses the interaction.

## Capture surface

The image presented for recognition during a capture session. It may originate from an image file, screenshot, screen region, window, or paused video frame.

## Text region

A spatially bounded piece of recognized text on a capture surface.

## OCR result

The recognized text regions, their spatial positions, reading order, confidence, and language information for one capture surface.

## Result surface

The ephemeral Flutter window that displays a capture surface, its spatial text regions, and synchronized selectable text for one capture session.

## Spatial selection

A selection of one or more text regions through their positions on a capture surface. Character-level selection belongs to the synchronized text representation rather than the image overlay.

## Local processing boundary

The privacy boundary under which captured pixels and recognized text remain on the user's device and are never sent to a remote service.
