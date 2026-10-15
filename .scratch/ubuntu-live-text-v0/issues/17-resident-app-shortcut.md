# 17: Resident app and shortcut activation

**What to build:** The app starts hidden at login, keeps the OCR worker warm,
and enters selection mode when the user's GNOME shortcut runs its selection
command. Replaces issue 08.

**Blocked by:** 16: Prove silent capture and active-display placement

**Status:** resolved (manual acceptance passed; onboarding steps delivered by 20)

- [x] The app uses a real application ID and ships a desktop file and an
  autostart entry installed by the dev script, starting hidden.
- [x] A second launch with the selection command activates the running
  instance instead of starting another one; a cold launch reaches the same
  flow.
- [x] Repeated activation while selection mode is open never creates a second
  capture, overlay, or worker.
- [x] Onboarding shows concise steps to add the GNOME custom shortcut and lets
  the user copy the command. The app never modifies GNOME settings.
- [x] The worker starts once at login and survives repeated selection
  sessions; existing recovery behaviour still applies.

## Implementation notes

The app ID is `dev.kiriglyph.Kiriglyph`. The GTK runner is a unique
`GApplication` that handles its command line: `--background` starts the engine
with the window hidden, `--select` is forwarded to the primary and delivered
to Dart on the `kiriglyph/app` channel, `--quit` lets Dart discard the session
and exits, and no argument shows the window. Closing the window of a resident
instance hides it and ends the session. `scripts/run-dev.sh` sets
`KIRIGLYPH_DEV_INSTANCE=1`, which makes the instance non-unique and
non-resident so `flutter run` never forwards to the installed app. A selection
command arriving while a capture or recognition is in flight is ignored. The
portal helper registers the app ID on its own D-Bus connection before any
other portal call (`--silent --app-id`). The app reads the returned
`~/Pictures/Screenshot*.png`, deletes exactly that path, and keeps a 0600 copy
in a 0700 directory under `$XDG_RUNTIME_DIR` for OCR and the workspace; the
copy is deleted when the session ends. Until issue 18 builds the overlay, a
selection opens the capture in the normal window. Install with
`scripts/install-desktop.sh`; the shortcut command is
`~/.local/bin/kiriglyph --select` (absolute path). Manual Wayland acceptance is
still pending.

The runner handles `command-line` as the first signal handler, connected in
`my_application_init`, not as the class vfunc. The `gtk` plugin pulled in by
Yaru connects its own `command-line` handler, and GApplication stops at the
first handler, so a vfunc never ran for forwarded launches: opening the app,
`--select`, and `--quit` were silently ignored.
