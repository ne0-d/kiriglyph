# 28: Preferences window, automatic shortcut, and save location

**What to build:** The normal window becomes a small native-looking
preferences and first-run window. A new user installs the `.deb`, opens
Kiriglyph, clicks one button, and the shortcut already works. The shortcut and
the folder for saved files can be changed in the window.

**Blocked by:** nothing.

**Status:** implemented; passes `scripts/check.sh full --build`; checked by the
owner on their desktop.

## Why

- The old window had two stacked headers (the GTK title bar and a Flutter bar
  with a Quit button), three container styles with bright outlines, and a
  1280x720 document-style page. It did not look like an Ubuntu 26.04 app.
- Setting the shortcut took five manual steps in GNOME Settings.
- Saved files always went to `~/Pictures`; there was no setting.

## Scope

1. **Window.** One native GTK header bar with a primary menu (About, Quit).
   The in-window Flutter bar and its Quit button are removed. Content is
   grouped rows in rounded surfaces with thin dividers (GNOME's boxed-list
   pattern), using the system accent and font through the Yaru theme. Default
   size about 600x700. Groups: Capture (screen access, shortcut), Files (save
   location), Background (launch at login, pause shortcut). A "Try it" button
   starts a selection. A banner shows what is missing.
2. **Shortcut.** A `ShortcutService` reads and writes the GNOME custom
   keybinding through `gsettings` (the same schema `kiriglyph --setup` uses).
   On first run, if no Kiriglyph shortcut exists, the app assigns the first
   free one from a short candidate list and says so in the window. An existing
   binding whose command is `kiriglyph --select` is adopted, not duplicated.
   The user can record a new one; the dialog warns about conflicts found in
   GNOME's custom, shell, mutter, window-manager, and media-key bindings, and
   refuses to replace one. If `gsettings` is unavailable the row falls back to
   the command and a Copy button.
3. **Save location.** `settings.json` under `$XDG_CONFIG_HOME/kiriglyph/`
   stores the folder. A native folder chooser (`chooseFolder`) sets it. All
   saves, Save as, and the status messages use it. Default stays Pictures.
4. **Screen access.** The window remembers that access was granted and shows
   "Allowed"; the overlay clears it if a capture is refused.

## Out of scope

- The `.deb` cannot set the shortcut: its maintainer scripts run as root,
  outside the user's session. The first launch does it instead.
- Publishing a GitHub release for a one-click `.deb` download.
- Changing where GNOME's screenshot portal writes its temporary capture; the
  app deletes that file immediately.

## Acceptance

- [x] `scripts/check.sh full --build` prints `CHECK PASSED`.
- [x] Tests cover: accelerator parsing and formatting, key-event capture,
      the gsettings service (create, adopt, update, conflicts, failure),
      automatic assignment on first run only, settings persistence, exports
      using the configured folder, and the new window's rows.
- [x] Manual (user-run): the window looks native; first run assigns a working
      shortcut; changing it works; the save folder change applies to Ctrl+S
      and Save as; Quit is in the header-bar menu. Reported working by the
      owner on 2026-10-29. The same pass found that **Open Kiriglyph** in the
      top-bar menu showed a black window after the window had been closed; fixed
      in issue 26's comments.

## Outcome

Decision record: [ADR 0003](../../../docs/adr/0003-app-sets-its-own-shortcut-on-first-run.md).

**What changed.**

- `app/lib/ui/settings/`: `preferences_page.dart` (the page and its rows),
  `settings_widgets.dart` (group, row, banner), `shortcut_dialog.dart` (records
  a key press, checks conflicts, saves). `app_header.dart`,
  `onboarding_view.dart` and `background_section.dart` are deleted.
- `app/lib/shortcut/`: `accelerator.dart` (parse, format, key capture),
  `shortcut_service.dart` (the `gsettings` adapter), `shortcut_controller.dart`
  (first-run assignment, change).
- `app/lib/settings/`: `app_settings.dart` (JSON in `$XDG_CONFIG_HOME`,
  atomic writes), `folder_picker.dart` (native chooser over the channel).
- Exports and the Save as dialog use the chosen folder; saved-file messages
  show its name.
- `app/linux/runner/my_application.cc`: header-bar menu (About, Quit), the
  `chooseFolder` method, the Save as dialog opens in the chosen folder, default
  window size 620x760.
- `scripts/build-deb.sh` also writes `dist/kiriglyph_amd64.deb`, a fixed name
  for a permanent release download link.

**Isolation.** Tests must never change the developer's GNOME shortcuts or
config. `app/test/flutter_test_config.dart` installs an in-memory settings
store and a fake shortcut service before every test file. After the full run,
the real custom shortcut and `~/.config` were unchanged.

**Bug caught by a test.** The accelerator parser accepted `<Control>` alone as
a key named `<Control>`; fixed so a key cannot start with `<`.

**Verified with a real `gsettings`.** The exact commands (list, create, set,
list-recursively) were run against a temporary keyfile store, not the
developer's dconf.

**Still open.**

- Manual check on a real desktop: window look, first-run shortcut, changing it,
  the save folder with Ctrl+S and Save as, Quit in the menu.
- Native code (menu, folder chooser) compiles but has no unit test.
- The shortcut recorder cannot capture keys that GNOME Shell takes first,
  which is correct because they are already in use.
- A clean-machine `.deb` run, and a published GitHub release for the one-click
  download link.
