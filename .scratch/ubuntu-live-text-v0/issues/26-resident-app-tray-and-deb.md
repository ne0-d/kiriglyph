# 26: Resident app, top-bar icon, instant open, and beta .deb

**What to build:** Kiriglyph starts in the background at login, shows an icon
in the GNOME top bar, opens the overlay instantly with no black flash, and
installs from a single `.deb` for a beta release.

**Blocked by:** nothing for the first two scopes. The `.deb` waits for the
worker dependencies from 25 (barcode decoder) to settle.

**Status:** approved; implementation in progress. Capture stays the current
Screenshot portal method; silent capture is explicitly out of scope.

## Scope

1. **Instant open, no black flash.** Cause: the fullscreen window is mapped
   before the captured frame exists, and Linux `first-frame` only covers engine
   startup. Fix: keep the pre-warmed window hidden; map it at opacity 0 only to
   learn placement; crop and publish the frozen frame while still invisible;
   after that frame's Dart post-frame callback and a native GTK frame-clock
   paint, reveal at opacity 1; start OCR crop encoding after reveal; hide (not
   just transparent) on dismissal. Validate at 100% and 125% and on two
   displays.
2. **Timing that separates phases.** Absolute activation-relative marks for
   forward, portal, read, decode, map, crop, reveal, PNG encode, OCR dispatch,
   OCR result, via the opt-in timing log. Phase marks are written without a
   synchronous flush on the hot path.
3. **Background start with an in-app toggle.** The resident app already starts
   hidden through the XDG autostart entry. Add "Launch at login": the app
   creates or removes its own `~/.config/autostart/dev.kiriglyph.Kiriglyph.desktop`
   (a `Hidden=true` override when the system entry exists). It never changes
   GNOME settings.
4. **Top-bar icon (StatusNotifierItem + dbusmenu).** Spike first: Dart `dbus`
   package implementation with a fake-bus test; fall back to `tray_manager`
   only if the spike shows dbusmenu in Dart is too costly. Menu: a disabled
   status line ("Ready", "Screenshot permission needed"), Select text or
   object, Open Kiriglyph, Launch at login (checkbox), Pause shortcut
   (checkbox), separator, Quit. "Pause shortcut" is an in-app flag that makes
   the resident app ignore `--select`. Symbolic icons
   (`kiriglyph-symbolic`, attention and busy variants); state is in the first
   menu label because the extension shows no tooltips. Probe
   `org.kde.StatusNotifierWatcher` ownership, watch `NameOwnerChanged`, and show
   a calm notice in the setup window if no host exists (vanilla GNOME). Quit
   reuses the existing `--quit` path and must stop the OCR and segmentation
   workers.
5. **Beta `.deb`.** Layout: `/usr/lib/kiriglyph` (Flutter bundle and private
   Python runtime), `/usr/bin/kiriglyph`, desktop entry, hicolor icons,
   AppStream metainfo, `/etc/xdg/autostart/dev.kiriglyph.Kiriglyph.desktop`.
   Bundle the EfficientSAM-Ti ONNX files (verified hashes, Apache-2.0 NOTICE)
   and the RapidOCR models inside the package; no runtime downloads. A
   `kiriglyph --setup` command guides first-run setup, including the GNOME
   shortcut, because packages must not write per-user settings. Package
   removal stops nothing by name; user data is removed only through an explicit
   in-app reset. Include a licence inventory of bundled components. Target:
   trustworthy Ubuntu 26.04 `.deb` for beta testers; not the official Debian
   archive.
6. **Clean-machine validation** of install, upgrade, and removal.

## Out of scope

Silent capture, resident memory reduction (separate later issue), Flatpak or
Snap, a signed APT repository, official Debian archive.

## Acceptance

- [ ] No visible black frame at activation on one and two displays, 100% and
  125%; the phase timings are recorded.
- [ ] Launch at login can be switched from the tray menu and the setup window,
  and survives restart.
- [ ] The top-bar icon appears on Ubuntu 26.04 with the AppIndicators
  extension; the menu items work; Quit leaves no worker processes; a notice
  appears when no host exists.
- [ ] `.deb` installs, runs, upgrades, and removes cleanly on a clean machine;
  `lintian` and `desktop-file-validate` findings are triaged.
- [ ] Orca can reach and read the tray menu (manual, recorded in issue 14).
