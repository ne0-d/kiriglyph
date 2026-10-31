# Changelog

All notable changes to Kiriglyph are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-29

The first public beta, for Ubuntu 26.04 with GNOME 50 on Wayland.

### Added

- Select text from the frozen screen with a drag, word, paragraph or loop, and copy it as plain text. Recognition runs locally.
- Cut out any object as a transparent PNG with a click or a loop, using a local segmentation model (EfficientSAM-Ti), with add and remove points and undo.
- Copy or save a screenshot of a rectangle, or of the whole display.
- Smart actions for links, email addresses, phone numbers and QR codes or barcodes, each confirmed before it opens, and a one-click web search.
- A preferences window: allow screen access, see and change the keyboard shortcut, choose the save folder, switch launch at login, and pause the shortcut.
- A GNOME shortcut that Kiriglyph assigns itself on first run (Ctrl+Super+T, or the next free choice).
- A top-bar icon with a menu, and a resident instance that starts hidden at login so the shortcut responds at once.
- An installable `.deb` that bundles its own Python runtime and every model, so nothing is downloaded when you use it.
- Keyboard-only use and screen-reader announcements. A full Orca run is still pending.

### Fixed

- The black flash when the overlay opens: the overlay now finds its display with a small probe window and maps fullscreen once, with the frozen frame already rendered.
- The top-bar icon disappearing after a quick restart: each instance now registers under its own bus name.
- A blank black window when opening Kiriglyph from the top-bar icon after the window was closed.

[0.1.0]: https://github.com/ne0-d/kiriglyph/releases/tag/v0.1.0
