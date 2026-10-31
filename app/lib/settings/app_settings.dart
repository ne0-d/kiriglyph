// Private fields are set from named parameters, which cannot start with an
// underscore, so initializing formals do not apply.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/export/subject_export.dart'
    show defaultPicturesDirectory;

/// What the user chose in the preferences window. Everything is optional so a
/// missing or damaged file means "use the defaults".
class AppSettings {
  const AppSettings({
    this.saveDirectory,
    this.screenAccessGranted = false,
    this.shortcutAutoSetupDone = false,
  });

  /// Folder for saved PNGs; null means the user's Pictures folder.
  final String? saveDirectory;

  /// The last screen-access request was granted.
  final bool screenAccessGranted;

  /// The first-run shortcut assignment already ran, so a shortcut the user
  /// later removes is not added back.
  final bool shortcutAutoSetupDone;

  AppSettings copyWith({
    String? saveDirectory,
    bool clearSaveDirectory = false,
    bool? screenAccessGranted,
    bool? shortcutAutoSetupDone,
  }) {
    return AppSettings(
      saveDirectory: clearSaveDirectory
          ? null
          : (saveDirectory ?? this.saveDirectory),
      screenAccessGranted: screenAccessGranted ?? this.screenAccessGranted,
      shortcutAutoSetupDone:
          shortcutAutoSetupDone ?? this.shortcutAutoSetupDone,
    );
  }

  Map<String, Object?> toJson() => {
    'saveDirectory': saveDirectory,
    'screenAccessGranted': screenAccessGranted,
    'shortcutAutoSetupDone': shortcutAutoSetupDone,
  };

  /// Reads settings, ignoring anything of the wrong shape.
  factory AppSettings.fromJson(Object? json) {
    if (json is! Map) {
      return const AppSettings();
    }
    final directory = json['saveDirectory'];
    return AppSettings(
      saveDirectory: directory is String && directory.isNotEmpty
          ? directory
          : null,
      screenAccessGranted: json['screenAccessGranted'] == true,
      shortcutAutoSetupDone: json['shortcutAutoSetupDone'] == true,
    );
  }
}

abstract interface class SettingsStore {
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
}

/// Settings in `$XDG_CONFIG_HOME/kiriglyph/settings.json`, written atomically.
class FileSettingsStore implements SettingsStore {
  FileSettingsStore({String? configHome, Map<String, String>? environment})
    : _configHome = configHome,
      _environment = environment ?? Platform.environment;

  final String? _configHome;
  final Map<String, String> _environment;

  File get _file {
    final root =
        _configHome ??
        _environment['XDG_CONFIG_HOME'] ??
        '${_environment['HOME']}/.config';
    return File('$root/kiriglyph/settings.json');
  }

  @override
  Future<AppSettings> load() async {
    try {
      final file = _file;
      if (!await file.exists()) {
        return const AppSettings();
      }
      return AppSettings.fromJson(jsonDecode(await file.readAsString()));
    } on FormatException {
      return const AppSettings();
    } on FileSystemException {
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    final file = _file;
    await file.parent.create(recursive: true);
    final temp = File(
      '${file.path}.tmp.${DateTime.now().microsecondsSinceEpoch}',
    );
    await temp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await temp.rename(file.path);
  }
}

/// Builds the real settings store. `test/flutter_test_config.dart` replaces
/// this so no test reads or writes the developer's own config folder.
SettingsStore Function() settingsStoreFactory = FileSettingsStore.new;

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => settingsStoreFactory(),
);

/// Whether PNGs can be saved in [path]: the folder exists or can be created,
/// and a file can be written and removed there.
Future<bool> canWriteTo(String path) async {
  try {
    final directory = Directory(path);
    await directory.create(recursive: true);
    final probe = File('${directory.path}/.kiriglyph-write-test');
    await probe.writeAsString('');
    await probe.delete();
    return true;
  } on FileSystemException {
    return false;
  }
}

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

class AppSettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.watch(settingsStoreProvider).load();

  Future<void> setSaveDirectory(String? path) => _update(
    (settings) => path == null || path.isEmpty
        ? settings.copyWith(clearSaveDirectory: true)
        : settings.copyWith(saveDirectory: path),
  );

  Future<void> setScreenAccessGranted(bool granted) =>
      _update((settings) => settings.copyWith(screenAccessGranted: granted));

  Future<void> markShortcutAutoSetupDone() =>
      _update((settings) => settings.copyWith(shortcutAutoSetupDone: true));

  Future<void> _update(AppSettings Function(AppSettings) change) async {
    final current = state.asData?.value ?? await future;
    final next = change(current);
    state = AsyncData(next);
    try {
      await ref.read(settingsStoreProvider).save(next);
    } on FileSystemException {
      // The choice still applies for this run; it is just not remembered.
    }
  }
}

/// The folder saved PNGs go to right now.
final saveDirectoryProvider = Provider<String>(
  (ref) =>
      ref.watch(appSettingsProvider).asData?.value.saveDirectory ??
      defaultPicturesDirectory(),
);

/// Short name of [saveDirectoryProvider] for status messages ("Pictures").
final saveFolderNameProvider = Provider<String>((ref) {
  final parts = ref
      .watch(saveDirectoryProvider)
      .split('/')
      .where((part) => part.isNotEmpty);
  return parts.isEmpty ? 'Pictures' : parts.last;
});
