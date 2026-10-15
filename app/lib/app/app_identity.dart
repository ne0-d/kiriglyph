import 'dart:io';

/// Must match `APPLICATION_ID` in `linux/CMakeLists.txt` and the desktop file
/// installed by `scripts/install-desktop.sh`; GNOME stores the screenshot
/// grant against it.
const kiriglyphAppId = 'dev.kiriglyph.Kiriglyph';

/// Launcher installed by `scripts/install-desktop.sh`.
String installedLauncherPath({Map<String, String>? environment}) {
  final home = (environment ?? Platform.environment)['HOME'] ?? '';
  return '$home/.local/bin/kiriglyph';
}

/// Command for a GNOME custom shortcut, quoted for GLib's shell parser.
String selectionCommand({Map<String, String>? environment}) {
  final launcher = installedLauncherPath(environment: environment);
  final quoted = RegExp(r'''[\s'"\\$`]''').hasMatch(launcher)
      ? "'${launcher.replaceAll("'", r"'\''")}'"
      : launcher;
  return '$quoted --select';
}
