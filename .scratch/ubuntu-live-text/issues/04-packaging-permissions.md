# Research packaging, permissions, and model distribution

Type: research
Status: resolved
Blocked by:

## Question

For an Ubuntu 24.04 local OCR application that captures user-selected screen content, compare Debian packages, Flatpak, Snap, and AppImage for portal access, global shortcuts, autostart or background service behavior, native dependencies, model-asset size and updates, sandboxing, signing, reproducible builds, and a trustworthy permission experience. Identify blockers to Ubuntu repository or GNOME ecosystem acceptance and license compatibility risks created by candidate runtimes and OCR models.

## Answer

- **Developer / alpha:** use a local native `.deb` for development and a signed, self-hosted Flatpak for alpha testing.
- **1.0 / upstream:** publish a strict Flathub Flatpak for 1.0; later pursue a Debian source package and Ubuntu `universe`. A strictly confined Snap is optional only after portal and focus testing. Do not use classic Snap or AppImage as an official privacy-enforcing channel.
- **Privacy boundary:** ship models in the signed artifact, make no runtime network requests, request only portal-mediated captures, and avoid broad filesystem access, autostart, background daemons, and persistent capture grants.
- **Blockers:** Ubuntu 24.04's GNOME 46 portal lacks Global Shortcuts, so users need a documented GNOME custom shortcut; the model and all native dependencies need artifact-level license/source/NOTICE/SBOM review; release signing, reproducible offline builds, key rotation, and security-update ownership must be established. Ubuntu archive submission also requires DFSG-compatible, source-buildable dependencies and model assets.

Full report: [Packaging and permissions research](../research/04-packaging-permissions.md)
