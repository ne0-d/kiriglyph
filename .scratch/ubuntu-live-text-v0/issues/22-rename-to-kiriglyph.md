# 22: Rename the project to Kiriglyph

**What to build:** The product is called **Kiriglyph** everywhere: code, app
identity, install scripts, UI text, and docs. "Live Text" is Apple's feature
name and stops being used as the product name.

**Blocked by:** none. Do this alone, before any other open ticket, because it
touches most files.

**Status:** resolved

Names and identifiers:

| What | Old | New |
| --- | --- | --- |
| Product name | Ubuntu Live Text, Live Text | Kiriglyph |
| Dart package | `ubuntu_live_text` | `kiriglyph` |
| Linux binary | `ubuntu_live_text` | `kiriglyph` |
| Application ID | `dev.livetext.LiveText` | `dev.kiriglyph.Kiriglyph` |
| Launcher and install dir | `~/.local/bin/live-text`, `~/.local/share/live-text` | `~/.local/bin/kiriglyph`, `~/.local/share/kiriglyph` |
| Desktop and autostart files | `dev.livetext.LiveText.desktop` | `dev.kiriglyph.Kiriglyph.desktop` |
| Environment variables | `LIVE_TEXT_*` | `KIRIGLYPH_*` |
| Method channel | `live_text/app` | `kiriglyph/app` |
| Python distribution and capture command | existing names containing `live-text` | `kiriglyph`, `kiriglyph-capture` |

The Python import package `worker` and the folder names `app/`, `worker/`, and
the repository directory stay as they are.

- [x] Every identifier in the table is renamed in code, build files (including
  `CMakeLists.txt` and the GTK runner), scripts, desktop-file templates, and
  tests; no old identifier remains except where listed below.
- [x] The window title, header, onboarding copy, tooltips, and notifications
  say Kiriglyph and no longer say "Live Text".
- [x] `install-desktop.sh` and `uninstall-desktop.sh` use the new identity. The
  uninstall script also removes leftovers of the old identity (old launcher,
  desktop files, autostart entry, and the old app's screenshot permission) if
  present, so older installs are cleaned up.
- [x] The shortcut command shown in onboarding is
  `~/.local/bin/kiriglyph --select` (absolute path).
- [x] The README and project docs use the new name. `.scratch/ubuntu-live-text-v0/`
  keeps its folder name as the stable tracker path, but its spec title and
  roadmap title say Kiriglyph. ADR 0001 gets a one-line note that the app ID
  is now `dev.kiriglyph.Kiriglyph`; the historical spike under
  `spikes/silent-capture/` is left unchanged.
- [x] A short "Name" paragraph in the README explains the name: kiri is Japanese
  for "cut" and glyph is a character, so the app cuts characters and subjects
  out of the screen.
- [x] `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build linux
  --debug`, and the worker tests all pass, and the whole repository search for
  `ubuntu_live_text`, `livetext`, `LIVE_TEXT`, and `Live Text` finds only the
  allowed leftovers (Apple's name in prose that discusses the origin of the
  feature, the old-identity cleanup in the uninstall script, and the spike).
