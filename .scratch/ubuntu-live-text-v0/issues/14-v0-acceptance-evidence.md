# 14: Publish combined V0 acceptance evidence

**What to build:** Maintainers can decide what enters the installable alpha
using reproducible evidence from the whole overlay: exact text selection and
Subject Lift.

**Blocked by:** 10: Publish the Text milestone acceptance evidence; 13: Export
a selected subject as transparent PNG.

**Status:** ready-for-human: run the manual checklist

- [ ] Shortcut-to-result walkthroughs cover text selection and transparent
  subject export from a web page, an image viewer, and a paused video frame.
- [ ] End-to-end latency and peak memory distinguish capture, OCR, image
  embedding, prompt updates, mask rendering, clipboard, and PNG encoding.
- [ ] Repeated sessions prove bounded workers, models, memory, temporary files,
  clipboard data, and capture state.
- [ ] Privacy checks show no network inference, content telemetry, persistent
  pixels, recognized text, masks, embeddings, or notification previews.
- [ ] Manual Ubuntu 26.04 GNOME 50 Wayland evidence covers cancellation,
  failure, multiple displays, fractional scaling, keyboard use, and Orca for
  both modes.
- [x] Known OCR and mask-quality limitations are documented with reproducible
  fixtures rather than hidden behind unsupported claims.
- [x] The report recommends the alpha feature set, architecture, adapters,
  packaging work (release build, start at login without the dev script), and
  any capability that must remain experimental.

## Acceptance kit

- Draft report: `.scratch/ubuntu-live-text-v0/acceptance/v0-acceptance-report.md`
- OCR evidence: `.scratch/ubuntu-live-text-v0/evidence/ocr-corpus-results.md`
- Subject evidence: `.scratch/ubuntu-live-text-v0/evidence/subject-corpus-results.md`
- Manual/resource/privacy scripts: `scripts/acceptance/`
