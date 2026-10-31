# 0003: The app sets its own GNOME shortcut on first run

**Status:** accepted. Implemented in issue 28.

## Context

Until now Kiriglyph never wrote GNOME settings. The user had to open Settings →
Keyboard → Custom Shortcuts and type the command in by hand, which was the
longest part of setup. The `.deb` cannot do it either: its maintainer scripts
run as root, outside the user's session and dconf database, and a package must
not write per-user settings.

## Decision

The running app configures its own shortcut, on the user's behalf and visibly.

- It uses `gsettings` with the same schema GNOME's Keyboard settings use
  (`org.gnome.settings-daemon.plugins.media-keys.custom-keybinding`), so the
  shortcut also appears and can be edited there.
- **First run only:** if no custom shortcut runs `kiriglyph --select`, it tries
  a short list of candidates (Ctrl+Super+T first) and sets the first one that
  nothing else uses. The window says "added for you". A flag in
  `settings.json` stops it adding one again if the user later removes it.
- **Adopt, do not duplicate:** an existing shortcut whose command contains
  `kiriglyph` and `--select` is used as is.
- **Conflicts:** before setting or changing a shortcut, the app scans custom
  shortcuts and the GNOME Shell, Mutter, window-manager and media-key schemas.
  It never overwrites a binding that is in use.
- **Change it in the window:** a dialog records the key press, refuses keys
  that would break typing (no Ctrl, Alt or Super), and shows what already uses
  a conflicting combination.
- **Fallback:** if `gsettings` is missing or fails, the window shows the
  command and a Copy button, as before.

`scripts/install-desktop.sh` still changes no GNOME settings; only the running,
user-visible app does.

## Alternatives considered

- **Keep the manual steps.** Safe, but every new user pays the setup cost.
- **Have the `.deb` do it.** Not possible: no user session, and not allowed.
- **Ask first with a confirm button.** The first-run window already requires
  one click (screen access), and the shortcut is shown, labelled, and
  changeable, so a second prompt added friction without protecting anything.
- **Talk to dconf over D-Bus.** More code for no gain over the `gsettings`
  command, which the existing `kiriglyph --setup` script already uses.

## Consequences

- Setup is: install, open, click Allow. The shortcut already works.
- The app depends on the `gsettings` command (package `libglib2.0-bin`, present
  on Ubuntu desktops). Without it the manual fallback appears.
- Keys that GNOME Shell takes before the app sees them cannot be recorded. That
  is correct: they are already in use.
- Tests must never run the real service. `test/flutter_test_config.dart`
  installs a fake for every test file.
