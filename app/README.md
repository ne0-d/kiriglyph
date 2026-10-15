# kiriglyph

Flutter Linux UI for Kiriglyph.

The normal window is setup-only (instant capture permission, GNOME shortcut,
quit). Text selection happens in the fullscreen selection overlay started by
`kiriglyph --select`, not by opening image files in the window.

Overlay controls:

- Text and object selection share one overlay: drag text to select characters,
  double-click a word, triple-click a paragraph, or draw a loop that the app can
  classify as text. Click an object to lift it, Shift+click to add foreground,
  Alt+click or right click to add background, and Ctrl+click/drag to force
  object selection over text.
- Ctrl+Z undoes the last object prompt step. Backspace/Delete removes the
  current object. Press `O` to show a keyboard object cursor, move it with
  arrow keys, and press Enter to lift the object under it.
- With a valid subject selected, Ctrl+C copies a transparent PNG image to the
  clipboard, Ctrl+S saves immediately to Pictures with a unique timestamped
  `kiriglyph-YYYYMMDD-HHMMSS.png` name, and Ctrl+Shift+S opens Save as...
  without hiding the overlay.
