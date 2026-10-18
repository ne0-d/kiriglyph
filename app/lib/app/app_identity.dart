import 'dart:io';

/// Must match `APPLICATION_ID` in `linux/CMakeLists.txt` and the desktop file
/// installed by `scripts/install-desktop.sh`; GNOME stores the screenshot
/// grant against it.
const kiriglyphAppId = 'dev.kiriglyph.Kiriglyph';

/// Launcher that starts this app: `KIRIGLYPH_LAUNCHER` (set by the `.deb`
/// launcher), otherwise the one `scripts/install-desktop.sh` installs.
String installedLauncherPath({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final override = env['KIRIGLYPH_LAUNCHER'];
  if (override != null && override.isNotEmpty) {
    return override;
  }
  return '${env['HOME'] ?? ''}/.local/bin/kiriglyph';
}

/// Command for a GNOME custom shortcut, quoted for GLib's shell parser.
String selectionCommand({Map<String, String>? environment}) {
  final launcher = installedLauncherPath(environment: environment);
  final quoted = RegExp(r'''[\s'"\\$`]''').hasMatch(launcher)
      ? "'${launcher.replaceAll("'", r"'\''")}'"
      : launcher;
  return '$quoted --select';
}
