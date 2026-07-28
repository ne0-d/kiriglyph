# Wayfinder map: Ubuntu Live Text

## Destination

Produce an evidence-backed, decision-complete product and technical
specification plus a dependency-ordered implementation backlog for Ubuntu
24.04 GNOME Wayland text selection and subject lifting, staged from feasibility
spikes through an open-source 1.0 release and eventual upstream integration.

## Notes

- Consult `research`, `grilling`, `domain-modeling`, and `codebase-design` while resolving this map.
- Prefer primary sources and record important claims with links and access dates.
- The product interaction is a user-invoked system-wide OCR overlay.
- Exact character dragging is a core Text requirement. Subject Lift is a
  separate local segmentation milestone supporting click or drawn-region
  prompts and transparent PNG export.
- Ubuntu 24.04, GNOME, and the default Wayland session are the first production target.
- V1 inputs are image files, screenshots, screen regions or windows, and paused video frames captured from the screen.
- Captured pixels and recognized text stay inside the local processing boundary.
- Capture occurs only after explicit user action; pixels are discarded when the capture session ends.
- Conventional local OCR and detection models are allowed; LLMs, generative models, and cloud inference are excluded.
- English recognition quality comes first behind a multilingual engine boundary.
- Delivery is staged: feasibility spikes, usable alpha, hardened 1.0, then upstream integration work.
- Flutter is a UI preference, not an architecture constraint; native system components are allowed where required.
- V1 is an installable user-space application or service with GNOME integration, not an Ubuntu or compositor patch.
- This effort covers Live Text-class OCR, selection, copy, and data-action hooks.
- Development V0 uses Flutter and Python to prove the capture-to-selection workflow. Native service architecture and production packaging are deferred until prototype evidence justifies them.

## Decisions so far

- [Research Ubuntu Wayland capture and overlay integration](issues/01-wayland-capture-overlay.md): Ubuntu 24.04 V1 should use a user-created GNOME shortcut and the interactive Screenshot portal; a custom Shell-level overlay is not available to an ordinary Wayland app.
- [Evaluate local OCR engines](issues/02-local-ocr-engine.md): Select the OCR engine through a pinned local bake-off of Tesseract, PaddleOCR/PP-OCRv6, and RapidOCR/ONNX Runtime; upstream metrics cannot decide the winner.
- [Evaluate Flutter and native system boundaries](issues/03-ui-stack-boundaries.md): Prefer a native GTK4 capture/overlay service with D-Bus boundaries; Flutter is suitable for an optional control UI, not the production overlay.
- [Research packaging, permissions, and model distribution](issues/04-packaging-permissions.md): Develop natively, alpha-test through a signed strict Flatpak, target Flathub for 1.0, and pursue Debian then Ubuntu `universe` after maturity.
- [Survey Linux OCR products and GNOME UX requirements](issues/05-linux-ocr-ux-landscape.md): The differentiator is an accessible spatial-text workflow on portal-backed GNOME Wayland with keyboard parity and privacy-minimal defaults.
- [Define the V1 interaction contract](issues/06-v1-interaction-contract.md):
  V1 uses GNOME capture followed by an ephemeral result surface with exact
  character-range selection, synchronized accessible text, local subject
  lifting, transparent export, keyboard parity, and no retained content.
- [Select the development V0 architecture and stack](issues/07-select-v1-architecture.md): Start with a Flutter Linux app and a long-lived local Python OCR worker over newline-delimited JSON; prove image OCR and spatial selection before portal, packaging, or native-service hardening.

## Not yet specified

- OCR engine, runtime format, model lifecycle, reading-order strategy, and multilingual extension seam.
- Interactive segmentation adapter, prompt contract, mask representation,
  alpha-edge policy, and production model lifecycle.
- Capture API, overlay mechanism, global shortcut path, multi-monitor behavior, and HiDPI coordinate model.
- Hardened production process boundaries, failure isolation, and whether prototype evidence justifies replacing any Flutter/Python component.
- Latency, memory, accuracy, startup, power, and supported-hardware release gates.
- Packaging format, sandbox posture, permissions UX, update strategy, and model-asset distribution.
- License, governance, contributor workflow, security reporting, release engineering, and upstream strategy.

## Out of scope

- Continuous or default background screen monitoring.
- Cloud OCR, remote processing, LLMs, and generative models.
- Continuous live-video OCR or text tracking in the first release.
- Semantic Visual Look Up, general object naming, and external knowledge
  results. Foreground/background subject lifting itself is in scope.
- Injecting selectable text directly into arbitrary third-party application widget trees.
- Patching GNOME Shell, Mutter, or Ubuntu system packages in V1.
- First-release parity across other Linux desktops, Windows, or macOS.
