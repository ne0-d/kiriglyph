import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/capture/instant_capture.dart'
    show selectionCommandProvider;
import 'package:kiriglyph/shortcut/accelerator.dart';

/// The shortcut could not be read or written.
class ShortcutException implements Exception {
  const ShortcutException(this.message);

  final String message;

  @override
  String toString() => 'ShortcutException($message)';
}

/// Kiriglyph's GNOME custom shortcut.
class ShortcutBinding {
  const ShortcutBinding({required this.accelerator, required this.path});

  final Accelerator accelerator;

  /// dconf path of the custom keybinding that holds it.
  final String path;
}

/// Something already using a shortcut the user wants.
class ShortcutConflict {
  const ShortcutConflict(this.accelerator, this.description);

  final Accelerator accelerator;
  final String description;
}

/// Reads and writes the GNOME custom shortcut that runs `kiriglyph --select`.
abstract interface class ShortcutService {
  /// The Kiriglyph shortcut, or null when there is none.
  Future<ShortcutBinding?> current();

  /// What already uses [accelerator], ignoring Kiriglyph's own shortcut.
  Future<ShortcutConflict?> findConflict(Accelerator accelerator);

  /// Creates or updates Kiriglyph's shortcut; throws [ShortcutException].
  Future<ShortcutBinding> set(Accelerator accelerator);
}

typedef GsettingsRunner = Future<ProcessResult> Function(List<String> args);

Future<ProcessResult> _runGsettings(List<String> args) async {
  try {
    return await Process.run('gsettings', args);
  } on ProcessException {
    throw const ShortcutException('gsettings is not available');
  }
}

/// [ShortcutService] over the `gsettings` command, using the schema GNOME's
/// own Keyboard settings use, so the shortcut shows up there too.
class GsettingsShortcutService implements ShortcutService {
  GsettingsShortcutService({required this.command, GsettingsRunner? run})
    : _run = run ?? _runGsettings;

  /// What the shortcut runs, such as `/usr/bin/kiriglyph --select`.
  final String command;
  final GsettingsRunner _run;

  static const _mediaKeys = 'org.gnome.settings-daemon.plugins.media-keys';
  static const _custom = '$_mediaKeys.custom-keybinding';
  static const _base =
      '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/';

  /// Schemas whose accelerators a new shortcut must not collide with.
  static const _scanned = {
    _mediaKeys: 'GNOME',
    'org.gnome.desktop.wm.keybindings': 'Window manager',
    'org.gnome.shell.keybindings': 'GNOME Shell',
    'org.gnome.mutter.keybindings': 'Mutter',
    'org.gnome.mutter.wayland.keybindings': 'Mutter',
  };

  Future<String> _read(List<String> args) async {
    final result = await _run(args);
    if (result.exitCode != 0) {
      throw ShortcutException('gsettings ${args.first} failed');
    }
    return (result.stdout as String).trim();
  }

  Future<void> _write(List<String> args) async {
    await _read(args);
  }

  static List<String> _quoted(String text) =>
      RegExp("'([^']*)'")
          .allMatches(text)
          .map((match) => match.group(1)!)
          .toList();

  /// A GVariant string literal.
  static String _variant(String text) =>
      "'${text.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

  Future<List<String>> _paths() async =>
      _quoted(await _read(['get', _mediaKeys, 'custom-keybindings']));

  Future<String> _value(String path, String key) =>
      _read(['get', '$_custom:$path', key]);

  Future<String> _plain(String path, String key) async {
    final quoted = _quoted(await _value(path, key));
    return quoted.isEmpty ? '' : quoted.first;
  }

  Future<bool> _isOurs(String path) async {
    final runs = await _value(path, 'command');
    return runs.contains('kiriglyph') && runs.contains('--select');
  }

  Future<String?> _ownPath(List<String> paths) async {
    for (final path in paths) {
      if (await _isOurs(path)) {
        return path;
      }
    }
    return null;
  }

  @override
  Future<ShortcutBinding?> current() async {
    final paths = await _paths();
    final own = await _ownPath(paths);
    if (own == null) {
      return null;
    }
    final accelerator = Accelerator.tryParse(await _plain(own, 'binding'));
    return accelerator == null
        ? null
        : ShortcutBinding(accelerator: accelerator, path: own);
  }

  @override
  Future<ShortcutConflict?> findConflict(Accelerator accelerator) async {
    final paths = await _paths();
    final own = await _ownPath(paths);
    for (final path in paths) {
      if (path == own) {
        continue;
      }
      final binding = Accelerator.tryParse(await _plain(path, 'binding'));
      if (binding == accelerator) {
        final name = await _plain(path, 'name');
        return ShortcutConflict(
          accelerator,
          name.isEmpty ? 'Another custom shortcut' : 'The shortcut "$name"',
        );
      }
    }
    for (final entry in _scanned.entries) {
      final String listing;
      try {
        listing = await _read(['list-recursively', entry.key]);
      } on ShortcutException {
        continue;
      }
      for (final line in listing.split('\n')) {
        final parts = line.split(' ');
        if (parts.length < 3) {
          continue;
        }
        for (final token in _quoted(parts.skip(2).join(' '))) {
          if (Accelerator.tryParse(token) == accelerator) {
            return ShortcutConflict(
              accelerator,
              '${entry.value}: ${parts[1].replaceAll('-', ' ')}',
            );
          }
        }
      }
    }
    return null;
  }

  @override
  Future<ShortcutBinding> set(Accelerator accelerator) async {
    final paths = await _paths();
    final own = await _ownPath(paths);
    final path = own ?? _newPath(paths);
    final schema = '$_custom:$path';
    await _write(['set', schema, 'name', _variant('Kiriglyph')]);
    await _write(['set', schema, 'command', _variant(command)]);
    await _write(['set', schema, 'binding', _variant(accelerator.toGtk())]);
    if (own == null) {
      await _write([
        'set',
        _mediaKeys,
        'custom-keybindings',
        '[${[...paths, path].map(_variant).join(', ')}]',
      ]);
    }
    return ShortcutBinding(accelerator: accelerator, path: path);
  }

  String _newPath(List<String> taken) {
    var path = '${_base}kiriglyph/';
    for (var attempt = 1; taken.contains(path); attempt++) {
      path = '${_base}kiriglyph$attempt/';
    }
    return path;
  }
}

/// Builds the real shortcut service. `test/flutter_test_config.dart` replaces
/// this so no test changes the developer's own GNOME shortcuts.
ShortcutService Function(String command) shortcutServiceFactory = (command) =>
    GsettingsShortcutService(command: command);

final shortcutServiceProvider = Provider<ShortcutService>(
  (ref) => shortcutServiceFactory(ref.watch(selectionCommandProvider)),
);
