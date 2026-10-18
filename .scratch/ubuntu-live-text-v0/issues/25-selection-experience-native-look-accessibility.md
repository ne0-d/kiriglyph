# 25: Selection experience, native Ubuntu look, and accessibility

**What to build:** Make the overlay a general "grab anything" tool and make the
whole app look and feel like a native, smooth Ubuntu application. One
delivery, built in two phases by agents that own disjoint files.

**Blocked by:** nothing. Runs in parallel with 26 (see file ownership there).

**Status:** approved; implementation in progress.

## Scope

1. **Native Ubuntu look.** Setup window, theme, and overlay chrome follow the
   Yaru design language: system font, GNOME light/dark and accent colour,
   symbolic icons, native spacing, rounded corners, proper header bar.
2. **Rectangle selection is the default tool.** Resize handles (24 px),
   click-click mode (first corner, second corner), keyboard model matching
   GNOME Shell's screenshot UI (arrows resize, Alt+arrows move, Ctrl for 1 px
   steps, Shift snaps to edges, R resets). Free-draw (loop) stays as a toolbar
   option.
3. **Outcome rules for any selection** (rectangle or loop). Text when at least
   60% of an OCR line box lies inside, otherwise object when a box-prompt mask
   is confident and fills more than 25% of the selection, otherwise plain
   image. All outcomes stay reachable as chips ("Copy text", "Lift object",
   "Copy screenshot", "Save screenshot"). Thresholds are named constants,
   tuned on the existing corpora.
4. **Save screenshots.** "Save screenshot" and "Copy screenshot" for the
   selected area (rectangle: exact crop; loop: bounding-box crop), and a
   toolbar button "Save full screenshot" for the whole captured display. All
   saves are direct to Pictures with `kiriglyph-YYYYMMDD-HHMMSS.png`
   (suffixes on collision) and keep the overlay open with a short status.
   Keys: Ctrl+S saves the primary output of the active selection (object PNG,
   or the screenshot of the area), Ctrl+Shift+S is Save as..., Ctrl+Shift+F
   saves the full screenshot.
5. **Smart detection in the selected text and image.** Emails, links, phone
   numbers (regex on the OCR text, pure and unit-tested) and QR codes and
   barcodes (permissively licensed decoder in the worker, run on the selection
   crop). Detected items appear as chips beside the selection: "Open link",
   "Compose email", "Call"/copy number, "Open code content", and "Copy". Nothing
   opens automatically. Only http, https, mailto and tel targets are allowed,
   and the target is shown before the user confirms.
6. **Search the web.** A button on selected text opens the selection in the
   user's default browser as a search. A browser CLI that honours the browser's
   own search engine is used where one exists (Firefox `--search`); otherwise
   the default browser is opened on a Google search URL via `xdg-open`.
   The label says the text leaves the computer only on click.
7. **Free-draw visuals.** Smoothed (centripetal Catmull-Rom) gradient trail
   that fades within about 300 ms and a dashed fill preview; solid 2 px line
   under reduced motion.
8. **Draggable toolbar.** Position remembered per display, clamped to the safe
   area, kept clear of the selection. Non-drag alternative: a "Move toolbar"
   menu (top, bottom, follow selection) and Alt+arrows on the focused toolbar.
9. **Persistent edge glow.** Visible the whole time the overlay is active. Calm
   static gradient frame with a 3:1 dark keyline; breathes only while OCR or
   segmentation is busy; static when GNOME `enable-animations` is false or
   `org.gnome.desktop.a11y.interface reduced-motion` is `reduce` (read over
   D-Bus because Flutter does not); in-app on/off toggle.
10. **Smooth, modern motion.** Short eased transitions for toolbar, selection,
    chips and hand-offs; all honour the reduced-motion policy above.
11. **Accessibility must-haves.**
    - Announcement audit: every state change goes through
      `SemanticsService.sendAnnouncement` (Flutter Linux ignores live regions
      and label changes, so the old live-region fallback does nothing).
    - Full keyboard map and a `?` / Ctrl+? cheat sheet; Escape steps back one
      level (rectangle, selection, overlay); F6 moves between canvas and
      toolbar; O / Shift+O cycle objects.
    - Visible focus ring (2 px, 3:1), 24 px minimum targets, a click or key
      alternative for every drag, selection cues that do not rely on colour
      alone, high-contrast and large-text legibility, GNOME cursor-size.

## Acceptance

- [ ] Rectangle is the default tool; handles, click-click mode, and the keyboard
  model work; free-draw is a toolbar option.
- [ ] Save/Copy screenshot work for rectangle and loop; Save full screenshot
  works; overlay stays open; unique names.
- [ ] Emails, links, phone numbers and QR/barcodes are detected with unit
  tests; nothing opens without a click; only allowed schemes open.
- [ ] Search the web opens the default browser; Firefox honours its own engine.
- [ ] Setup window and overlay use the Yaru look and follow light/dark/accent.
- [ ] Toolbar can be dragged and moved by keyboard/menu; position remembered.
- [ ] Edge glow persists, goes static under reduced motion, and has a toggle.
- [x] Announcements, keyboard map, cheat sheet, focus rings, and target sizes
  pass the widget-test checks (`overlay_keyboard_map_test.dart`,
  `overlay_accessibility_test.dart`).
- [ ] The assistive-technology run (Orca, keyboard only, high contrast, 200%
  text, reduced motion, magnifier) is recorded in issue 14.

## Later (not in this issue)

Copy options (remove line breaks), find in screenshot, read aloud, redact, OCR
language packs, Orca caret-navigation spike, Settings/About/Licences screen.

## Accessibility decisions

- Flutter's Linux embedder speaks only `SemanticsService.sendAnnouncement`
  (ATK notifications); live regions, dialogs, route changes and label changes
  are silent there (flutter/flutter#194045), so every state change goes
  through one rate-limited `OverlayAnnouncer` and the live-region status is
  only a fallback.
- GNOME 50 Reduced Motion is `org.gnome.desktop.a11y.interface
  reduced-motion`, read over the Settings portal; cursor size is
  `org.gnome.desktop.interface cursor-size`, read the same way and failing
  open to 24.
- Caret navigation of recognised text exists in Flutter only for text fields;
  a hidden mirrored read-only text field is a later spike, so the overlay
  moves its own selection by key and announces counts, never the text.
- Object selection by keyboard (O / Shift+O) cycles a 3 by 3 grid of areas
  that text does not mostly cover, because there is no object proposal source
  yet; Enter segments at the chosen point and the arrows fine-tune it. Click-click
  rectangles are shadowed by the object click, so the rectangle's keyboard
  path (R, then arrows) is the pointer-free alternative.

## Manual accessibility test plan

Run on a real GNOME session from the shortcut, with the setting changed before
the overlay opens. Record results in issue 14.

1. **Orca:** start Orca (Super+Alt+S). Open the overlay and listen for "Kiriglyph
   capture open, N lines found, press question mark for help". Press `?` and
   read the cheat sheet; Escape closes it. Check that selecting speaks counts
   and never the recognised text, that copy and save say what and where, that
   errors interrupt, and that closing is spoken.
2. **Keyboard only:** without touching the pointer select text (arrows,
   Ctrl+arrows, Home/End, Ctrl+Shift+Up/Down), copy, make a rectangle with R and
   the arrows, pick an object with O and Enter, save with Ctrl+S, save the full
   screen with Ctrl+Shift+F, F6 to the toolbar and back, Alt+arrows to move it,
   Escape three times to step back and close.
3. **GNOME high contrast:** the toolbar, chips and help panel are opaque with a
   solid 2 px border; outlines, handles and the object cursor stay visible on
   dark and light screenshots; the focus ring is visible on every control.
4. **200% text:** toolbar, chips and the help panel stay on screen and readable,
   nothing is cut off at 480 px wide.
5. **Reduced motion:** with Settings > Accessibility > Reduced Motion on, the
   glow is static, the sweep and stroke fade are gone, and transitions are
   instant.
6. **Sticky, slow and mouse keys:** shortcuts with Ctrl, Shift and Alt still work
   with sticky keys on, slow keys do not swallow R, O or arrows, and mouse keys
   can drive the rectangle and the toolbar grip.
7. **Magnifier at 3x:** the focus ring, handles and object cursor are easy to
   follow; the magnifier tracks focus as it moves between canvas, toolbar and
   chips; the cursor-size setting enlarges the handles and the object cursor.
