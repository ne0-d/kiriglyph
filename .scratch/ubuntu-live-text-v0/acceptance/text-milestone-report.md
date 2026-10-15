# Text Milestone Acceptance Report

**Status:** draft, ready for human desktop run.

## Hardware For Automated Evidence

- CPU: AMD Ryzen 5 5600H with Radeon Graphics
- Cores: 12
- RAM: MemTotal 15685340 kB
- OS: Ubuntu 26.04.1 LTS
- GNOME: GNOME Shell 50.1
- Session: wayland

## Checklist Mapping

1. Shortcut-to-selectable-text latency: **MANUAL-PENDING**. Run the installed release build with `KIRIGLYPH_TIMING_LOG=1`, then perform one-display and two-display captures. The Dart log starts at the earliest Dart-visible forwarded `--select`; native command-line forwarding before Dart is not timed.
2. Idle/peak memory and 50 activations: **MANUAL-PENDING**. User command: `bash scripts/acceptance/measure-resources.sh --activations 50` or, after the grant, `bash scripts/acceptance/measure-resources.sh --auto 50`. Self-test passed: process growth 0, RSS growth 0.00%, runtime files 0, Pictures screenshots 0.
3. Privacy tests: **MANUAL-PENDING**. User command: `python3 scripts/acceptance/privacy_check.py --canary '<known visible text>'`. Synthetic self-test passed: clean state PASS; planted canary and PNG leaks FAIL.
4. OCR corpus: **MEASURED** by `worker/.venv/bin/python scripts/acceptance/ocr-corpus-eval.py`. Results: 7/7 images recognized, mean CER 0.005, line recall/precision 1.000/1.000, geometry failures 0, reading-order errors 0, mean worker OCR 398.9 ms. Paragraph grouping matched 4/7 fixtures exactly; `dark_code` and `ui_buttons` are acceptable non-prose splits, while `two_columns` is a real follow-up risk because OCR returned row-wise reading order.
5. Manual GNOME Wayland coverage: **MANUAL-PENDING**. Use the consolidated checklist below.
6. Keyboard and Orca findings: **AUTOMATED-PASS** for widget tests; **MANUAL-PENDING** for real Orca and compositor focus. Relevant tests are in `app/test/overlay_accessibility_test.dart`.
7. Architecture/OCR recommendation: **MANUAL-PENDING** final decision; draft recommendation below.

## Results Already Provided By The User

- Selection overlay manual acceptance passed on one and two displays at 100% and 125% in issue 18.
- Circle selection and triple-click paragraph selection manual acceptance passed in issue 19.

## Consolidated Manual Checklist

| # | Procedure | Pass/Fail | Notes |
|---:|---|---|---|
| 1 | First-run permission: open Kiriglyph, click Enable instant capture, allow GNOME access, then close. |  |  |
| 2 | Revoked grant: revoke screenshots permission, press shortcut, confirm onboarding notice and no stuck overlay. |  |  |
| 3 | One display at 100% and 125%: web page, image viewer, paused video, drag/double/triple/circle select and copy. |  |  |
| 4 | Two displays at 100% and 125%: pointer on each display, only that display freezes, other stays live. |  |  |
| 5 | Keyboard-only: no click after shortcut; arrows, Ctrl+Shift+Up/Down, Ctrl+A, Ctrl+C, Escape. |  |  |
| 6 | Orca: recognizing, ready, copied, no-text and failure announcements; recognized text not spoken unprompted. |  |  |
| 7 | Resource run: paste summary from `measure-resources.sh --activations 50`. |  |  |
| 8 | Privacy run: display canary before capture, dismiss, then paste PASS/FAIL from `privacy_check.py --canary`. |  |  |

## Recommendations (Draft, Pending Manual Results)

Keep Flutter plus Python for V0 if the manual timing/resource run confirms bounded resident behavior and keyboard focus is acceptable. Keep RapidOCR as the V0 adapter because geometry and corpus evidence are strong enough for an alpha, but file a follow-up for multi-column reading order before claiming robust article extraction. Code and button clusters should stay treated as non-prose layouts unless user testing says paragraph snapping should include them. Run the planned production OCR bake-off before hardening; reopen native-service research only if release-build latency, focus, Orca, or resource results fail on the real desktop.
