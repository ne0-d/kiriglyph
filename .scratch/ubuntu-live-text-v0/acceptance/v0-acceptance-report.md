# V0 Acceptance Report

**Status:** draft, ready for human desktop run.

## Hardware For Automated Evidence

- CPU: AMD Ryzen 5 5600H with Radeon Graphics
- Cores: 12
- RAM: MemTotal 15685340 kB
- OS: Ubuntu 26.04.1 LTS
- GNOME: GNOME Shell 50.1
- Session: wayland

## Checklist Mapping

1. Shortcut-to-result walkthroughs for text and Subject export: **MANUAL-PENDING**. Use the consolidated checklist below on web page, image viewer, and paused video frame.
2. End-to-end latency and peak memory: **MEASURED** for worker corpora; **MANUAL-PENDING** for desktop capture/paint/export. Subject worker protocol measured median embed 1260.1 ms, median prompt 132.3 ms, peak RSS 594.1 MiB. Timing log phases are available behind `KIRIGLYPH_TIMING_LOG`.
3. Repeated sessions boundedness: **MEASURED** for segmentation worker: 20 sequential spawn/embed/prompt/close sessions left zero mask/runtime files. **MANUAL-PENDING** for resident app, clipboard, capture state, and OCR over 50 real activations.
4. Privacy checks: **AUTOMATED-PASS** for synthetic privacy self-test; **MANUAL-PENDING** for real session canary and process sockets after desktop use.
5. Manual GNOME Wayland coverage: **MANUAL-PENDING** for cancellation, failure, multiple displays, fractional scaling, keyboard use, and Orca in both Text and Subject modes.
6. OCR and mask-quality limitations: **MEASURED**. OCR corpus mean CER 0.005 with synthetic limitations. Paragraph grouping matched 4/7 fixtures exactly: code and UI-button splits are acceptable non-prose behavior, while the two-column fixture exposes a real reading-order follow-up risk. Subject fixtures produced 28 `ok` and 1 `suspect_full_image`; synthetic masks are not real screenshots.
7. Alpha recommendation: **MANUAL-PENDING** final decision; draft recommendation below.

## Results Already Provided By The User

- Selection overlay manual acceptance passed on one and two displays at 100% and 125% in issue 18.
- Circle selection and triple-click paragraph selection manual acceptance passed in issue 19.

## Consolidated Manual Checklist

| # | Procedure | Pass/Fail | Notes |
|---:|---|---|---|
| 1 | First-run permission flow, then shortcut launch from the real GNOME shortcut. |  |  |
| 2 | Revoked grant and portal/capture failure paths show recoverable UI and no leftover files. |  |  |
| 3 | Text mode on web page, image viewer, paused video; one and two displays; 100% and 125%. |  |  |
| 4 | Subject mode on web page, image viewer, paused video; click, lasso, clear, retry, cancel. |  |  |
| 5 | Keyboard-only Text and Subject modes, including Ctrl+M, Ctrl+C, Ctrl+S, Backspace/Delete, Escape. |  |  |
| 6 | Orca in both modes: status is announced, recognized text is not spoken unprompted, controls are named. |  |  |
| 7 | Copy image after overlay dismissal into Firefox, Chromium, GIMP, LibreOffice, and Telegram. |  |  |
| 8 | Save PNG chooser from overlay: cancel restores, success dismisses, overwrite decline preserves file. |  |  |
| 9 | 50-activation resource script summary pasted here. |  |  |
| 10 | Privacy canary script result pasted here. |  |  |

## Recommendations (Draft, Pending Manual Results)

Alpha should keep Text mode enabled if the release-build desktop run confirms acceptable shortcut-to-first-paint latency, bounded memory, and focus/Orca behavior, with a follow-up ticket for multi-column reading order before broad article/document claims. Subject mode should remain experimental: EfficientSAM-Ti is local, bounded, and protocol-clean in fixtures, but real screenshot quality, paste targets, save chooser behavior, and edge polish still need human evidence. Packaging work before alpha: release build install path, start-at-login without the dev script, explicit model fetch/install step, and a choice between `.deb` convenience and Flatpak portal/permission constraints.
