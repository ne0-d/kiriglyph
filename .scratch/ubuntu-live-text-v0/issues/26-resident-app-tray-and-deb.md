# 26: Resident app, top-bar icon, instant open, and beta .deb

**What to build:** Kiriglyph starts in the background at login, shows an icon
in the GNOME top bar, opens the overlay instantly with no black flash, and
installs from a single `.deb` for a beta release.

**Blocked by:** nothing for the first two scopes. The `.deb` waits for the
worker dependencies from 25 (barcode decoder) to settle.

**Status:** implemented; passes `scripts/check.sh full --build`; the `.deb` is
checked on a clean Ubuntu (see Acceptance). Manual acceptance of the Orca tray
menu and the display checks is still open. The instant
open design in scope 1 was **superseded by issue 27**. Capture stays the
current Screenshot portal method; silent capture is explicitly out of scope.

## Scope

1. **Instant open, no black flash.** *Superseded by
   [27](27-no-black-frame-gnome-wayland.md) and
   [ADR 0002](../../../docs/adr/0002-overlay-maps-once-on-a-located-display.md):
   the opacity gating below did nothing on Wayland, and Mutter paints black
   behind any non-opaque fullscreen window. The overlay now finds its display
   with a probe window and maps fullscreen once, with the frozen frame already
   rendered.* Original text: Cause: the fullscreen window is mapped
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
- [x] `.deb` installs, runs, upgrades, and removes cleanly on a clean machine;
  `lintian` and `desktop-file-validate` findings are triaged. Lintian reports
  nothing outside the documented overrides; `desktop-file-validate` and
  `appstreamcli` pass. Install, start (virtual display), upgrade, remove and
  purge pass in a clean rootless Ubuntu 26.04 root filesystem
  (`scripts/acceptance/deb-clean-room/`). A run on a full Wayland desktop VM is
  still a manual step.
- [ ] Orca can reach and read the tray menu (manual, recorded in issue 14).

## Comments

- **Tray icon vanished after a quick restart (fixed).** The tray item used the
  fixed bus name `dev.kiriglyph.Kiriglyph.StatusNotifierItem`. When the app
  restarted quickly (a reinstall, for example), the new instance registered
  that name just before GNOME's AppIndicators host finished cleaning up the old
  instance, and the clean-up removed the entry by name, deleting the new
  registration. The app still owned the name, so nothing looked wrong; the icon
  just never showed. Reproduced by recording the session bus: the host's
  `StatusNotifierItemUnregistered` for the name arrived 0.1 s after the new
  registration, and 2 of 4 quick restarts lost the icon. The item is now
  registered as `org.freedesktop.StatusNotifierItem-<pid>-1`, as other tray
  apps do, so an old instance's clean-up cannot touch a new one. After the
  fix, 9 of 9 quick restarts registered. Test: `status_notifier_test.dart`.
- **Tray "Open Kiriglyph" showed a black window (fixed).** Closing the window
  switches the main screen off (the hidden window keeps its last frame, which
  must be transparent). The tray's Open called Dart's `present`, which only maps
  the window, so it mapped that transparent frame over Mutter's black backdrop.
  The launcher and a second launch go through native `present_window`, which
  asks Dart to paint the main screen first, so they were fine. The tray now calls
  a new `requestPresent` channel method that enters the same path. Test:
  `selection_overlay_test.dart`, "opening the window from the tray paints the
  main screen before it maps" (fails on the old wiring).
- **Release preparation for 0.1.0.** Licence chosen
  ([ADR 0004](../../../docs/adr/0004-apache-2-licence.md)); the package now has a
  Debian-format copyright file, changelog and man page, AppStream homepage and
  release data, a notice generator that reads real Dart licences and leaves out
  development-only packages, and no build-machine path in its RUNPATH
  (`CMAKE_BUILD_WITH_INSTALL_RPATH`). The empty `prerm` was dropped.
  `lintian`, `desktop-file-validate` and `appstreamcli` findings are triaged in
  [docs/packaging.md](../../../docs/packaging.md). Install, upgrade, removal and
  purge were run in a throwaway Ubuntu 26.04 rootfs (see that page for what it
  does and does not cover).
