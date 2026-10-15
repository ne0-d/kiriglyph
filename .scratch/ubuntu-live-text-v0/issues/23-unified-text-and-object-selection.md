# 23: One interface for text and object selection

**What to build:** The overlay has no Text | Subject toggle. The user acts on
what they see, and the app decides from where they click or draw whether they
mean text or an object, like Circle to Search. Both kinds of selection live in
the same overlay, with one selection active at a time.

**Blocked by:** the "Fixes after desktop testing" work on 12 and 13 (mask
display, pop-out highlight, action chip, unique file names, click mask quality).

**Status:** implemented in the Flutter overlay; real desktop/manual acceptance
for difficult visual cases remains under issue 14.

## Interaction grammar

Text is decided by the OCR geometry that already exists: a point is "on text"
when it falls inside a recognised line quad (small tolerance, a few pixels).

| Gesture | Starts on text? | Result |
| --- | --- | --- |
| Drag | yes | Text selection by character (unchanged) |
| Double-click / triple-click | yes | Word / paragraph (unchanged) |
| Click (stroke under the click threshold) | no | Lift the object under the pointer (foreground point) |
| Click | yes | Clears the selection; no object lift |
| Drag or loop | no | Classified on release, see below |
| Shift+click | no | Adds a foreground point to the active object |
| Alt+click or right-click | no | Adds a background point to the active object (refine) |
| Ctrl held at pointer-down | any | Force object: click lifts the object under the pointer even on text; drag draws an object lasso |

Loop classification on release (a pure, unit-tested function, not widget code):

- Compute the characters whose centres fall inside the loop (existing
  even-odd rule), their summed box area, and the loop area.
- **Text** when the loop contains enough characters and the text covers a real
  share of the loop (start from at least 3 characters and a text-area ratio of
  at least about 0.12; keep these as named constants, tune with the fixtures
  and report values). Text selection then snaps to whole paragraphs exactly as
  today.
- **Object** otherwise: the loop is sent as a box plus polygon prompt.
- After either result, a small hint chip beside the selection offers the other
  reading: "Selected as text - Select as image instead" or "Selected as image -
  Select as text instead". Choosing it re-applies the same loop the other way.
  The chip disappears when the selection is cleared or a new gesture starts.

Pointer cue: the cursor is the text cursor over recognised text and a precise
or pointer cursor elsewhere, so the outcome of a click is visible before it
happens.

## One active selection

- Starting a text selection clears an active object, and lifting an object
  clears the text selection.
- Ctrl+C copies the active selection: text for text, the transparent PNG for an
  object. Ctrl+S saves the object. Ctrl+A selects all text. Backspace or the
  chip's cross clears an object; Ctrl+Z undoes an object prompt step. Esc keeps
  closing the overlay.
- The toolbar loses the Text | Subject toggle and the Ctrl+M shortcut. It
  shows Copy and Copy all while text exists (disabled with a reason when a
  screen has no text), and Close. The object's actions live on its chip near
  the object (issue 12/13 fixes).
- The idle hint reads "Drag across text, or click an object". On a screen
  without text it reads "Click or draw around an object".

## Acceptance

- [x] The Text | Subject toggle and its shortcut are gone from the toolbar, tab
  order, tooltips, semantics, and docs; Text selection behaviour is unchanged
  when the user only works with text.
- [x] The gesture table above holds, driven by a pure arbitration function with
  unit tests for each row and boundary (click versus drag threshold, pointer
  just inside and outside a line quad, Ctrl override, a loop around a
  paragraph, a loop around a photo, a loop around a photo with a caption, a
  loop that contains a few stray characters).
- [ ] The classification constants are justified with fixtures (the OCR corpus
  and the real screenshot fixture) and listed in the issue with the
  measured outcomes. Open: the shipped values (3 characters, 0.12) are the
  starting values and the table below uses synthetic loops. Tune them by
  running real OCR on the real screenshot fixture (Google Images page) and
  recording loops around a paragraph, a card with a caption, and a logo.
- [x] Hint chip flips the interpretation of the last loop, deterministically,
  without a new capture or a new embedding.
- [x] One selection is active at a time; copy, save, clear, undo, and Esc follow
  the rules above, with tests including semantics and announcements
  (concise, never speaking recognised text).
- [x] Cursor feedback matches the outcome.
- [x] Missing model: a click on a non-text area shows the existing message with
  the exact `kiriglyph-fetch-models` command once, and text selection is
  unaffected.
- [x] Object preparation is requested after OCR as today; a click before it is
  ready is held and applied when ready, latest wins.
- [x] Legible and keyboard-operable in light, dark, high contrast, and at 2.0x
  text, with the hint chip and action chip in the documented tab order.
- [x] Keyboard-only users can lift an object: define and document a keyboard
  path (for example a focus-ring "object picker" that steps through a coarse
  grid or through detected subject candidates, or arrow-key cursor movement
  with Enter), since click and lasso are pointer gestures. If this proves too
  large, record it as a known limitation in the issue and report it.
- [x] Known limitations are documented with evidence: text over photos
  (subtitles, memes), logos containing letters, and tiny objects.
- [x] README, app README, spec, roadmap, and issues 09, 12, 13 are updated
  to remove the toggle; issue 14's manual checklist covers the new gestures.

## Implementation evidence

Arbitration lives in `app/lib/selection/selection_intent.dart`. Constants:

| Constant | Value |
| --- | --- |
| Minimum characters in loop | 3 |
| Minimum text-area ratio | 0.12 |
| Text hit tolerance | 3 source pixels |

Classifier fixture outcomes:

| Fixture | Characters | Text ratio | Outcome |
| --- | ---: | ---: | --- |
| Paragraph loop | 5 | >= 0.12 | text |
| Photo loop with no text | 0 | 0 | object |
| Photo with small caption | 3 | < 0.12 | object |
| Stray edge letters | 2 | varies | object |

Known limitations:

- Subtitles, memes, and other text over photos can classify as text when enough
  subtitle area is inside the loop; Ctrl-drag forces object selection.
- Logos with several large letters can classify as text; Ctrl-click or Ctrl-drag
  is the escape hatch.
- Tiny objects are best selected by click or the keyboard object cursor rather
  than lasso.
