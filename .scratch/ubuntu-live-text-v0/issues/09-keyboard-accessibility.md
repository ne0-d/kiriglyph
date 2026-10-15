# 09: Keyboard focus and screen-reader basics for the overlay

**What to build:** The selection overlay is usable without a pointer and
exposes its content and state to assistive technology. Most keyboard selection
already exists from issue 06 (arrows, Shift+arrows, Ctrl+A, Ctrl+C); this ticket
closes the gaps the overlay introduced.

**Blocked by:** none

**Status:** resolved (implemented and covered by widget tests; Orca,
keyboard-only and compositor-focus checks remain manual and are recorded in 10)

Already delivered, verify only: arrow and Shift+arrow selection, Ctrl+A,
Ctrl+C, Escape dismissal, reduced-motion handling for glow, sweep, and circle
stroke. Re-verified by `test/overlay_accessibility_test.dart` and the existing
overlay tests (reduced motion keeps the status text and drops the sweep).

- [ ] The overlay takes keyboard focus when it opens, so Escape, arrows, and
  Ctrl+C work without a first click, including when opened from the shortcut.
  *Flutter side implemented and tested: the canvas has primary focus as soon as
  text is ready and Escape works while recognizing. Whether GNOME Wayland gives
  the window keyboard focus when the shortcut opens it is implemented as
  `gtk_window_present` (unchanged); manual verification pending in issue 10.*
- [ ] Tab order in the overlay is canvas, Copy, Copy all, Close. Dismissing
  returns focus to the previously active application.
  *Tab order implemented and tested (including Shift+Tab, wrap-around, and
  recognized lines not being tab stops); disabled Copy buttons are skipped.
  Dismissal hides the window, and GNOME's compositor then picks the next
  window to focus; this is not controlled by the app and is unverified.
  Manual verification pending in issue 10.*
- [x] A keyboard-only path selects a whole paragraph (for example
  Ctrl+Shift+Down or Alt+arrows), since circle and triple-click are pointer
  gestures. The key is shown in the toolbar tooltips.
  *Ctrl+Shift+Down selects the first paragraph, Ctrl+Shift+Up the last; repeat
  to add the neighbouring paragraph. A partial selection first snaps to whole
  paragraphs. Shown in the Copy tooltip; Copy all and Close tooltips show
  Ctrl+A and Esc.*
- [x] Recognized text is exposed in reading order through Flutter semantics in
  the overlay as well as the window.
  *One node per line ("Line N: text", `selected` flag, ordinal sort key by
  reading order) under a "Recognized text" canvas node that carries the key
  hints and "N characters selected". The frozen screenshot is excluded. The
  window no longer shows recognized text.*
- [ ] Concise announcements for recognizing, no text found, copied, and failure
  states. Recognized content is never spoken automatically.
  *Implemented, manual verification pending in issue 10. Announcements go
  through `SemanticsService.sendAnnouncement` (the Linux embedder forwards it
  as an ATK announcement) when `MediaQuery.supportsAnnounce` is true; otherwise
  the status text is a live region for transient states only. Selection
  changes and the idle hint are never announced, and no message contains
  recognized text. Also announced: "N lines found" when text becomes ready.*
- [x] Text and controls remain legible in light, dark, and high-contrast themes
  at large text sizes; no state relies on colour alone.
  *Status text is tested at 4.5:1 (light, dark) and 7:1 (high contrast); the
  toolbar wraps and stays on screen at 2.0x text on 800 px and 480 px wide
  displays; failure messages are never truncated; selection has an outline and
  a "N lines selected" status in addition to the tint; recognizing is text
  plus optional motion.*
- [ ] Orca and keyboard-only findings, including known limitations, are
  recorded in the acceptance report (10) rather than claimed here.

## Manual checks for issue 10

With Orca running (`orca` or Super+Alt+S) and from the real shortcut:

1. **Focus on open:** press the shortcut with another app focused. Without
   clicking, press an arrow key, then Ctrl+C, then Esc. Note whether the
   overlay got focus and how long it took. Repeat on the second display.
2. **Focus on close:** after Esc and after Close, which window is focused?
   Typing should go to the app that was active before the shortcut.
3. **Tab:** Tab and Shift+Tab visit canvas, Copy, Copy all, Close; Copy is
   skipped until something is selected. Orca names each control.
4. **Paragraph keys:** Ctrl+Shift+Down and Ctrl+Shift+Up select whole
   paragraphs on a real page; the status says "N lines selected"; Ctrl+C
   pastes them with a blank line between paragraphs.
5. **Announcements:** Orca speaks "Recognizing text…", then "N lines found",
   and "Copied …" after Ctrl+C. It must not read recognized text unprompted,
   and must not read each arrow-key selection change. Try the no-text case
   (a blank wallpaper) and a copy failure if one can be provoked. If nothing
   is spoken, `MediaQuery.supportsAnnounce` may be false on this build or ATK
   announcements may not reach Orca; record which.
6. **Reading order:** with Orca flat review or Tab/arrow object navigation,
   lines are visited top to bottom, each as "Line N: text", and selected lines
   are reported as selected. The screenshot should not be announced as an
   image.
7. **Appearance:** check the overlay with light, dark, and Settings >
   Accessibility > High Contrast, and at Large Text on and off.

Known limitations: the overlay is a single borderless window, so Orca may
treat it as one unnamed window; line-level semantics are per line, not per
paragraph; Orca caret browsing of the recognized text is not provided.
