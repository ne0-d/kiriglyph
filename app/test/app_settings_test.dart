import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/export/subject_export.dart'
    show defaultPicturesDirectory;
import 'package:kiriglyph/providers.dart';
import 'package:kiriglyph/settings/app_settings.dart';

import 'support/settings_fakes.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('kiriglyph-cfg-'));
  tearDown(() => root.deleteSync(recursive: true));

  group('FileSettingsStore', () {
    test('starts with the defaults when there is no file', () async {
      final settings = await FileSettingsStore(configHome: root.path).load();

      expect(settings.saveDirectory, isNull);
      expect(settings.screenAccessGranted, isFalse);
      expect(settings.shortcutAutoSetupDone, isFalse);
    });

    test('saves and loads every setting', () async {
      final store = FileSettingsStore(configHome: root.path);

      await store.save(
        const AppSettings(
          saveDirectory: '/home/me/Shots',
          screenAccessGranted: true,
          shortcutAutoSetupDone: true,
        ),
      );
      final loaded = await FileSettingsStore(configHome: root.path).load();

      expect(loaded.saveDirectory, '/home/me/Shots');
      expect(loaded.screenAccessGranted, isTrue);
      expect(loaded.shortcutAutoSetupDone, isTrue);
      expect(File('${root.path}/kiriglyph/settings.json').existsSync(), isTrue);
    });

    test('ignores a damaged or wrongly shaped file', () async {
      final file = File('${root.path}/kiriglyph/settings.json')
        ..createSync(recursive: true);
      final store = FileSettingsStore(configHome: root.path);

      file.writeAsStringSync('{not json');
      expect((await store.load()).saveDirectory, isNull);

      file.writeAsStringSync('["a list"]');
      expect((await store.load()).saveDirectory, isNull);

      file.writeAsStringSync(
        '{"saveDirectory": 7, "screenAccessGranted": "yes"}',
      );
      final loaded = await store.load();
      expect(loaded.saveDirectory, isNull);
      expect(loaded.screenAccessGranted, isFalse);
    });

    test('uses XDG_CONFIG_HOME, then ~/.config', () async {
      await FileSettingsStore(
        environment: {'XDG_CONFIG_HOME': '${root.path}/xdg', 'HOME': '/nope'},
      ).save(const AppSettings(screenAccessGranted: true));
      await FileSettingsStore(environment: {'HOME': '${root.path}/home'})
          .save(const AppSettings(screenAccessGranted: true));

      expect(
        File('${root.path}/xdg/kiriglyph/settings.json').existsSync(),
        isTrue,
      );
      expect(
        File('${root.path}/home/.config/kiriglyph/settings.json').existsSync(),
        isTrue,
      );
    });
  });

  group('settings controller', () {
    ProviderContainer containerWith(MemorySettingsStore store) {
      final container = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('changes are remembered', () async {
      final store = MemorySettingsStore();
      final container = containerWith(store);
      await container.read(appSettingsProvider.future);
      final controller = container.read(appSettingsProvider.notifier);

      await controller.setSaveDirectory('/home/me/Shots');
      await controller.setScreenAccessGranted(true);
      await controller.markShortcutAutoSetupDone();

      expect(store.value.saveDirectory, '/home/me/Shots');
      expect(store.value.screenAccessGranted, isTrue);
      expect(store.value.shortcutAutoSetupDone, isTrue);
      expect(
        container.read(appSettingsProvider).value!.saveDirectory,
        '/home/me/Shots',
      );
    });

    test('clearing the folder goes back to Pictures', () async {
      final store = MemorySettingsStore(
        const AppSettings(saveDirectory: '/home/me/Shots'),
      );
      final container = containerWith(store);
      await container.read(appSettingsProvider.future);

      await container.read(appSettingsProvider.notifier).setSaveDirectory(null);

      expect(store.value.saveDirectory, isNull);
      expect(container.read(saveDirectoryProvider), defaultPicturesDirectory());
    });

    test('the folder name is what the messages show', () async {
      final store = MemorySettingsStore(
        const AppSettings(saveDirectory: '/home/me/Documents/Screens/'),
      );
      final container = containerWith(store);
      await container.read(appSettingsProvider.future);

      expect(container.read(saveFolderNameProvider), 'Screens');
    });
  });

  group('exports use the chosen folder', () {
    test('screenshots are saved there', () async {
      final folder = Directory('${root.path}/Shots');
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWithValue(
            MemorySettingsStore(AppSettings(saveDirectory: folder.path)),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(appSettingsProvider.future);

      final outcome = await container
          .read(screenshotExportControllerProvider)
          .save(Uint8List.fromList([1, 2, 3]));

      expect(outcome.savedName, isNotNull);
      expect(File('${folder.path}/${outcome.savedName}').existsSync(), isTrue);
    });
  });

  test(
    'canWriteTo is true for a folder it can create, false otherwise',
    () async {
      expect(await canWriteTo('${root.path}/new/deeper'), isTrue);
      expect(Directory('${root.path}/new/deeper').existsSync(), isTrue);
      expect(await canWriteTo('/proc/kiriglyph-cannot-write'), isFalse);
    },
  );
}
