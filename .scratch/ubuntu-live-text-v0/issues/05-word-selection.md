# 05: Validate and enable word selection

**What to build:** A user can select individual words where RapidOCR's derived word geometry is demonstrably reliable, while the application safely falls back to line selection for results that do not satisfy geometry invariants.

**Blocked by:** 03: Select and copy recognized lines.

**Status:** ready-for-agent

- [ ] Non-sensitive fixtures cover punctuation, URLs, code, multiple spaces, small fonts, rotation, and perspective.
- [ ] Word text, ordering, containment, overlap, and source-image polygon invariants are defined and tested.
- [ ] Invalid or ambiguous word geometry never disables the corresponding selectable line.
- [ ] Pointer and keyboard selection can move between validated words and extend a spatial selection.
- [ ] Copied word selections preserve deterministic reading order and sensible spacing.
- [ ] The worker contract remains engine-neutral and identifies whether word geometry is native, derived, or unavailable.
