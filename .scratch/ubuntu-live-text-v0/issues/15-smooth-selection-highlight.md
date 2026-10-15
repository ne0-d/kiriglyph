# 15: Smooth text selection highlight

**What to build:** Selecting recognized text looks like selecting text in a
normal document: one continuous highlight band per line, with no per-character
boxes, outlines, or gaps at spaces.

**Blocked by:** none

**Status:** resolved

- [x] Each selected line renders one band from the first selected character's
  leading edge to the last selected character's trailing edge, including
  spaces and punctuation between them.
- [x] The band follows the line's tilt or perspective using the line geometry,
  not an axis-aligned rectangle.
- [x] No outline is drawn around characters or bands; the fill uses the system
  selection colour.
- [x] Region and character outlines are hidden by default; hover shows no
  boxes.
- [x] The pointer is a text cursor over recognized text.
- [x] Existing drag, double-click, triple-click, keyboard, and copy behaviour
  is unchanged.

## Implementation notes

The canvas now paints selected text as one fill-only band per line. Character
lines derive the band from the first selected character's leading edge and the
last selected character's trailing edge, projected onto the full line polygon
for consistent height and tilt; line-only regions fill the line polygon and
keep only a subtle focused underline for keyboard accessibility.
