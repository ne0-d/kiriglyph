import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/shortcut/accelerator.dart';
import 'package:kiriglyph/shortcut/shortcut_service.dart';

const _mediaKeys = 'org.gnome.settings-daemon.plugins.media-keys';
const _base =
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/';

/// An in-memory `gsettings` that prints values the way the real one does.
class FakeGsettings {
  final values = <String, String>{};
  final listings = <String, String>{};
  final calls = <List<String>>[];
  bool missing = false;

  /// Defines a custom keybinding the way GNOME Settings would.
  void addCustom(String name, String command, String binding, String slug) {
    final path = '$_base$slug/';
    final list = _paths()..add(path);
    values['$_mediaKeys|custom-keybindings'] =
        '[${list.map((p) => "'$p'").join(', ')}]';
    final schema = '$_mediaKeys.custom-keybinding:$path';
    values['$schema|name'] = _print(name);
    values['$schema|command'] = _print(command);
    values['$schema|binding'] = _print(binding);
  }

  List<String> _paths() {
    final raw = values['$_mediaKeys|custom-keybindings'];
    if (raw == null) {
      return [];
    }
    return RegExp("'([^']*)'")
        .allMatches(raw)
        .map((match) => match.group(1)!)
        .toList();
  }

  /// gsettings prints a string with double quotes if it has a single quote.
  static String _print(String text) =>
      text.contains("'") ? '"$text"' : "'$text'";

  static String _unquote(String literal) {
    if (literal.startsWith('[')) {
      return literal;
    }
    final inner = literal.substring(1, literal.length - 1);
    return inner.replaceAll(r"\'", "'").replaceAll(r'\\', r'\');
  }

  Future<ProcessResult> run(List<String> args) async {
    calls.add(args);
    if (missing) {
      throw const ShortcutException('gsettings is not available');
    }
    switch (args.first) {
      case 'get':
        final key = '${args[1]}|${args[2]}';
        var value = values[key];
        if (value == null && args[2] == 'custom-keybindings') {
          value = '@as []';
        }
        value ??= "''";
        return ProcessResult(0, 0, '$value\n', '');
      case 'set':
        final raw = args[3];
        values['${args[1]}|${args[2]}'] = raw.startsWith('[')
            ? raw
            : _print(_unquote(raw));
        return ProcessResult(0, 0, '', '');
      case 'list-recursively':
        final listing = listings[args[1]];
        return listing == null
            ? ProcessResult(0, 1, '', 'No such schema')
            : ProcessResult(0, 0, listing, '');
    }
    return ProcessResult(0, 2, '', 'unknown');
  }

  String? valueOf(String path, String key) =>
      values['$_mediaKeys.custom-keybinding:$path|$key'];
}

void main() {
  const command = '/usr/bin/kiriglyph --select';
  late FakeGsettings gsettings;
  late GsettingsShortcutService service;

  setUp(() {
    gsettings = FakeGsettings();
    service = GsettingsShortcutService(command: command, run: gsettings.run);
  });

  Accelerator accel(String text) => Accelerator.tryParse(text)!;

  group('current', () {
    test('is null when nothing is set up', () async {
      expect(await service.current(), isNull);
    });

    test('finds the shortcut that runs kiriglyph --select', () async {
      gsettings.addCustom('Other', 'gedit', '<Super>e', 'custom0');
      gsettings.addCustom(
        'Kiriglyph',
        '/home/me/.local/bin/kiriglyph --select',
        '<Control><Super>t',
        'custom1',
      );

      final binding = await service.current();

      expect(binding!.accelerator, accel('<Control><Super>t'));
      expect(binding.path, '${_base}custom1/');
    });

    test('adopts a shortcut with a quoted launcher path', () async {
      gsettings.addCustom(
        'Kiriglyph',
        "'/home/me/my apps/kiriglyph' --select",
        '<Control><Alt>k',
        'custom0',
      );

      expect((await service.current())!.accelerator, accel('<Control><Alt>k'));
    });

    test('is null when the shortcut has no keys', () async {
      gsettings.addCustom('Kiriglyph', command, '', 'custom0');

      expect(await service.current(), isNull);
    });
  });

  group('set', () {
    test('creates the shortcut and lists it', () async {
      final binding = await service.set(accel('<Control><Super>t'));

      expect(binding.path, '${_base}kiriglyph/');
      expect(gsettings.valueOf(binding.path, 'name'), "'Kiriglyph'");
      expect(gsettings.valueOf(binding.path, 'command'), "'$command'");
      expect(gsettings.valueOf(binding.path, 'binding'), "'<Control><Super>t'");
      expect(
        gsettings.values['$_mediaKeys|custom-keybindings'],
        "['${_base}kiriglyph/']",
      );
      expect(
        (await service.current())!.accelerator,
        accel('<Control><Super>t'),
      );
    });

    test('keeps the keybindings that were already there', () async {
      gsettings.addCustom('Other', 'gedit', '<Super>e', 'custom0');

      await service.set(accel('<Control><Alt>k'));

      expect(
        gsettings.values['$_mediaKeys|custom-keybindings'],
        "['${_base}custom0/', '${_base}kiriglyph/']",
      );
    });

    test('updates its own shortcut instead of adding a second', () async {
      gsettings.addCustom(
        'Kiriglyph',
        '/home/me/.local/bin/kiriglyph --select',
        '<Control><Super>t',
        'custom0',
      );

      final binding = await service.set(accel('<Control><Alt>k'));

      expect(binding.path, '${_base}custom0/');
      expect(gsettings.valueOf(binding.path, 'binding'), "'<Control><Alt>k'");
      expect(
        gsettings.values['$_mediaKeys|custom-keybindings'],
        "['${_base}custom0/']",
      );
    });

    test('quotes a command that contains a single quote', () async {
      final quoted = GsettingsShortcutService(
        command: "'/home/me/my apps/kiriglyph' --select",
        run: gsettings.run,
      );

      final binding = await quoted.set(accel('<Super>k'));

      final stored = gsettings.calls.firstWhere(
        (call) => call.length > 3 && call[2] == 'command',
      );
      expect(stored[3], r"'\'/home/me/my apps/kiriglyph\' --select'");
      expect(
        gsettings.valueOf(binding.path, 'command'),
        "\"'/home/me/my apps/kiriglyph' --select\"",
      );
    });

    test('avoids a path another entry already uses', () async {
      gsettings.addCustom('Other', 'gedit', '<Super>e', 'kiriglyph');

      final binding = await service.set(accel('<Control><Alt>k'));

      expect(binding.path, '${_base}kiriglyph1/');
    });

    test('reports that gsettings is missing', () async {
      gsettings.missing = true;

      expect(
        () => service.set(accel('<Super>k')),
        throwsA(isA<ShortcutException>()),
      );
    });
  });

  group('findConflict', () {
    test('finds another custom shortcut', () async {
      gsettings.addCustom(
        'Terminal',
        'gnome-terminal',
        '<Control><Alt>k',
        'c0',
      );

      final conflict = await service.findConflict(accel('<Control><Alt>k'));

      expect(conflict!.description, 'The shortcut "Terminal"');
    });

    test('ignores its own shortcut', () async {
      await service.set(accel('<Control><Alt>k'));

      expect(await service.findConflict(accel('<Control><Alt>k')), isNull);
    });

    test('finds a built-in GNOME shortcut', () async {
      gsettings.listings['org.gnome.shell.keybindings'] =
          "org.gnome.shell.keybindings toggle-overview ['<Super>s']\n"
          "org.gnome.shell.keybindings focus-active-notification ['<Super>n']\n";

      final conflict = await service.findConflict(accel('<Super>s'));

      expect(conflict!.description, 'GNOME Shell: toggle overview');
    });

    test('finds a window manager shortcut with several keys', () async {
      gsettings.listings['org.gnome.desktop.wm.keybindings'] = "org.gnome.desktop.wm.keybindings close ['<Alt>F4', '<Control><Alt>k']\n";

      final conflict = await service.findConflict(accel('<Control><Alt>k'));

      expect(conflict!.description, 'Window manager: close');
    });

    test(
      'is clear when nothing uses it, even if a schema is missing',
      () async {
        gsettings.listings['org.gnome.shell.keybindings'] =
            "org.gnome.shell.keybindings toggle-overview ['<Super>s']\n";

        expect(await service.findConflict(accel('<Control><Super>t')), isNull);
      },
    );
  });
}
