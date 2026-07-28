# 12: Select a subject by click or drawn region

**What to build:** A user can switch to Subject mode, click a visible subject
or draw around it, inspect the resulting mask, and refine or clear the
selection without sending pixels off-device.

**Blocked by:** 11: Select a local interactive segmentation adapter.

**Status:** blocked

- [ ] The capture result exposes explicit Text and Subject modes without
  ambiguous pointer behavior.
- [ ] One image embedding is reused within the active capture session and
  discarded when that session ends.
- [ ] A click supplies a point prompt; a drawn region supplies a bounded lasso
  or box prompt understood by the model-neutral adapter.
- [ ] Add, remove, refine, replace, and clear interactions produce deterministic
  prompt state with short progress and cancellation behavior.
- [ ] The selected mask remains aligned while the image is fitted, resized,
  zoomed, or panned.
- [ ] Empty, unstable, edge-touching, and multi-subject masks have clear
  recoverable outcomes.
- [ ] Pointer, keyboard, semantics, state, geometry, cancellation, and
  responsive widget tests cover the workflow.
