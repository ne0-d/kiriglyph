# Survey Linux OCR products and GNOME UX requirements

Type: research
Status: resolved
Blocked by:

## Question

Which maintained Linux tools already provide screenshot OCR, spatial text interaction, or related workflows, and what gaps remain? Survey projects such as NormCap, TextSnatcher, Frog, gImageReader, and relevant GNOME utilities from their primary repositories. Also extract applicable GNOME Human Interface Guidelines and accessibility expectations for shortcuts, overlays, keyboard-only use, screen readers, focus, notifications, theming, and destructive or privacy-sensitive actions.

## Answer

Full report: [Linux OCR UX landscape](../research/05-linux-ocr-ux-landscape.md)

### Product differentiation

- Existing screenshot OCR tools predominantly implement “select a region, then copy/show plain text.” gImageReader preserves spatial hOCR structure, but as a document workbench rather than a transient desktop overlay.
- No surveyed tool documents the complete combination of GNOME Wayland portal capture, keyboard-only region control, screen-reader semantics, selectable word/block geometry, focus restoration, and privacy-minimal defaults. That combination is the product opportunity.
- Document OCR is a separate workflow: gImageReader and OCRmyPDF establish useful import, structure, export, security, and typed-error precedents, but should not determine the lightweight capture interaction.

### UX obligations

- Direct GNOME/GTK guidance calls for keyboard parity and logical focus order; short accessible names and correct roles, states, properties, and relations; standard shortcut behavior; high-contrast and large-text testing; system-responsive theming; translatable text; and feedback that is not available only through notifications.
- Product recommendations derived from that guidance are to request user-configurable global shortcuts through the GlobalShortcuts portal, prefer Screenshot portal v3 `Area` capture with capability detection, make region geometry keyboard operable, restore focus after capture, expose recognized content through standard selectable text semantics, and announce completion and failures without automatically speaking sensitive text.
- Treat cancellation as normal and distinguish portal denial/unavailability, capture failure, no text, missing OCR language/engine, OCR failure or timeout, and clipboard failure. Keep OCR local by default, delete portal files on every terminal path, omit recognized content from telemetry and default notifications, and make persistent history opt-in.

### Blockers

- Screenshot portal v3 targets and GlobalShortcuts support depend on the deployed Ubuntu/GNOME portal backend, so the implementation needs runtime capability checks and tested fallbacks rather than assuming current documentation matches every target release.
- Portal-provided selection delegates keyboard and assistive-technology behavior to the desktop backend; the surveyed projects do not provide end-to-end Orca or keyboard-only acceptance evidence. A custom spatial overlay therefore needs its own accessible interaction model and verification.
- GNOME Shell private screenshot internals provide tighter integration but are brittle and unsuitable as the primary standalone architecture. Current source behavior also does not always match the latest packaged release, so the exact Ubuntu package/runtime matrix must be validated during implementation.
