# 24: Desktop testing round 2 fixes

**What to build:** Fix the defects found while using the real overlay on GNOME
Wayland after issue 23. Four user-reported items, one process change.

**Blocked by:** none

**Status:** ready-for-agent

## Findings and decisions

1. **Highlight only the border.** The object currently gets a tinted fill
   over its whole area and looks like it glows. Draw the object in its natural
   colours with a clean double outline (dark + light) only. Keep a light dim
   of everything outside the object (reduced from the current strength) so it
   still reads as lifted. No tint fill. Reduced motion stays honoured.
2. **Export stuck on "Exporting subject..." and survives reopening.** The busy
   state outlives the operation and the session. Required: export state is
   scoped to one operation and one overlay session; any outcome, error,
   timeout, dismissal, or new session clears it; every native call
   (clipboard, chooser) responds on every path; a watchdog clears busy after a
   bounded time and reports a failure message. Reproduce at unit level and add
   a regression test (start export, dismiss, new session: not busy).
3. **Overlay closes on Save.** Cause: by design from issue 13, Save PNG hides
   the overlay while the GTK chooser is open and dismisses on success. A hidden
   window cannot parent a Wayland dialog reliably, which also explains item 2.
   Decision: **Save PNG saves immediately** to the user's Pictures folder with
   the unique timestamp name, with no dialog; the overlay stays open and shows
   "Saved to Pictures/<name>" (and the object stays selected so the user can
   also copy). The chooser stays available as **Save as... (Ctrl+Shift+S)**
   with the overlay kept visible while it is open (never hidden); the
   focus-loss guard stays. If the Pictures folder is not writable, fall back
   to the chooser.
4. **Lasso is a region of interest, not a hard clip.** Drawing around an
   object must capture the whole identified object, even where the loop is
   rough or cuts slightly through the object's edge, and several whole
   objects inside the loop are combined into one clean PNG. Today the polygon
   is applied as a hard constraint, which cuts the sides off the object.
   Required: do not intersect the final mask with the polygon; treat the loop
   as a box plus seeds; keep every identified object whose majority lies
   inside the loop in full; exclude objects mostly outside it. Budget about
   600 ms per lasso prompt.
5. **Detection quality (holes, wrong shapes).** Holes in the green apples and
   odd bulges on the iStock apple are likely caused by our own post-processing
   (the uniform-background trim, the lasso seed trim, hole-fill limits) and
   the hard polygon clip, not only by the model's size. Required: ablate each
   rule on the real screenshots (including the new ones), remove or fix the
   rules that damage objects (light-coloured parts such as flesh or
   highlights must not be treated as background), and only then compare
   EfficientSAM-S or SAM 2.1 Tiny as an upgrade (report only; do not swap
   models without data and the user's approval; limits: embed under about
   2.5 s, memory under about 1.6 GiB).

## Process change

Agents were spending too much time on repeated test runs and renders. New
rules, recorded in the development workflow playbook: targeted tests while
working, one full suite run at the end, no repeated full-suite runs, visual
renders only when geometry or painting changed, and time-boxed iteration.

## Acceptance

- [x] Object shows an outline only; no tint fill; subject in natural colour.
- [x] Export cannot get stuck; regression test for dismiss and new session.
- [x] Save PNG saves directly with a unique name and keeps the overlay open;
  Save as... works without hiding the overlay.
- [x] Lasso captures whole objects within the loop; multi-object union; no
  hard polygon clip; rough loops that slightly cut an object still return it.
  Worker now treats polygon prompts as ROI seeds and unions candidate objects
  by majority overlap instead of intersecting the final mask with the polygon.
- [ ] No holes in light-coloured parts of objects on the real fixtures; the
  iStock apple click has no bulge; the green apples are whole. Worker cleanup
  was adjusted to avoid hard clipping and to fill enclosed holes, but the new
  attached round-2 screenshots are overlay-state images with painted masks in
  the pixels, so they are not valid source images for judging segmentation
  quality directly.
- [x] Report on model upgrade candidates with numbers.

## Evidence for items 1-3

- Highlight: `SubjectMaskPainter` now draws the outside dim at 0.30 and the
  dark/light outline only; the subject mask is no longer filled with tint.
- Stuck export: regression test `dismiss during stuck export clears busy for
  next session` starts a never-completing save, dismisses, starts a new overlay,
  and asserts `Exporting subject...` is gone; export operations are bounded by
  a watchdog and clear busy in `finally`.
- Save PNG: `SubjectExportController.save` writes atomically to Pictures with
  `kiriglyph-YYYYMMDD-HHMMSS.png`, adding `-2`, `-3` before overwrite; Save as
  remains on Ctrl+Shift+S and keeps the overlay visible.
