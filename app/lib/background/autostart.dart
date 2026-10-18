// Private fields are set from named parameters, which cannot start with an
// underscore, so initializing formals do not apply.
// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/app/app_identity.dart';

const kiriglyphDesktopId = '$kiriglyphAppId.desktop';

class LaunchAtLoginService {
  LaunchAtLoginService({
    String? configHome,
    String? systemEntryPath,
    String? launcherPath,
    Map<String, String>? environment,
  }) : _environment = environment ?? Platform.environment,
       _configHome = configHome,
       _systemEntryPath = systemEntryPath,
       _launcherPath = launcherPath;

  final Map<String, String> _environment;
  final String? _configHome;
  final String? _systemEntryPath;
  final String? _launcherPath;

  String get _configRoot =>
      _configHome ??
      _environment['XDG_CONFIG_HOME'] ??
      '${_environment['HOME']}/.config';

  String get _launcher =>
      _launcherPath ?? installedLauncherPath(environment: _environment);

  File get _userEntry => File('$_configRoot/autostart/$kiriglyphDesktopId');

  File get _systemEntry =>
      File(_systemEntryPath ?? '/etc/xdg/autostart/$kiriglyphDesktopId');

  Future<bool> isEnabled() async {
    final user = _userEntry;
    if (await user.exists()) {
      final contents = await user.readAsString();
      return !_hasHiddenOverride(contents);
    }
    return _systemEntry.existsSync();
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      await _writeAtomically(_userEntry, _enabledEntry());
      return;
    }
    if (await _systemEntry.exists()) {
      await _writeAtomically(_userEntry, _hiddenEntry());
    } else if (await _userEntry.exists()) {
      await _userEntry.delete();
    }
  }

  String _enabledEntry() =>
      '''
[Desktop Entry]
Type=Application
Name=Kiriglyph
Comment=Keeps Kiriglyph ready for its selection shortcut
Exec=$_launcher --background
Icon=kiriglyph-symbolic
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
''';

  String _hiddenEntry() => '''
[Desktop Entry]
Type=Application
Name=Kiriglyph
Hidden=true
''';

  static bool _hasHiddenOverride(String contents) {
    return contents
        .split('\n')
        .map((line) => line.trim())
        .any((line) => line.toLowerCase() == 'hidden=true');
  }

  static Future<void> _writeAtomically(File file, String contents) async {
    await file.parent.create(recursive: true);
    final temp = File(
      '${file.path}.tmp.${DateTime.now().microsecondsSinceEpoch}',
    );
    await temp.writeAsString(contents);
    await temp.rename(file.path);
  }
}

final launchAtLoginServiceProvider = Provider<LaunchAtLoginService>(
  (ref) => LaunchAtLoginService(),
);

final launchAtLoginProvider =
    AsyncNotifierProvider<LaunchAtLoginController, bool>(
      LaunchAtLoginController.new,
    );

class LaunchAtLoginController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.watch(launchAtLoginServiceProvider).isEnabled();

  Future<void> setEnabled(bool enabled) async {
    state = const AsyncLoading<bool>();
    final service = ref.read(launchAtLoginServiceProvider);
    await service.setEnabled(enabled);
    state = AsyncData(await service.isEnabled());
  }
}
