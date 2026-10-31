import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/app/app_lifecycle.dart';
import 'package:kiriglyph/app/app_shell.dart';
import 'package:kiriglyph/background/autostart.dart';
import 'package:kiriglyph/background/shortcut_pause.dart';
import 'package:kiriglyph/capture/session_image_store.dart';
import 'package:kiriglyph/overlay/selection_overlay.dart';
import 'package:kiriglyph/providers.dart';

import 'support/overlay_fakes.dart';

void main() {
  group('launch at login', () {
    late Directory root;
    late Directory config;
    late File systemEntry;
    late LaunchAtLoginService service;

    setUp(() {
      root = Directory.systemTemp.createTempSync('autostart-');
      config = Directory('${root.path}/config')..createSync();
      systemEntry = File('${root.path}/etc/xdg/autostart/$kiriglyphDesktopId')
        ..createSync(recursive: true)
        ..writeAsStringSync('[Desktop Entry]\nHidden=false\n');
      service = LaunchAtLoginService(
        configHome: config.path,
        systemEntryPath: systemEntry.path,
        launcherPath: '/home/user/.local/bin/kiriglyph',
      );
    });

    tearDown(() {
      root.deleteSync(recursive: true);
    });

    test('writes a user autostart entry atomically when enabled', () async {
      await service.setEnabled(true);

      final file = File('${config.path}/autostart/$kiriglyphDesktopId');
      expect(file.existsSync(), isTrue);
      expect(
        file.readAsStringSync(),
        contains('Exec=/home/user/.local/bin/kiriglyph --background'),
      );
      expect(file.readAsStringSync(), isNot(contains('Hidden=true')));
      expect(await service.isEnabled(), isTrue);
    });

    test('disables a system autostart entry with a Hidden override', () async {
      await service.setEnabled(false);

      final file = File('${config.path}/autostart/$kiriglyphDesktopId');
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), contains('Hidden=true'));
      expect(await service.isEnabled(), isFalse);
    });

    test('removes the user entry when no system autostart exists', () async {
      systemEntry.deleteSync();
      await service.setEnabled(true);
      await service.setEnabled(false);

      final file = File('${config.path}/autostart/$kiriglyphDesktopId');
      expect(file.existsSync(), isFalse);
      expect(await service.isEnabled(), isFalse);
    });
  });

  test('pause shortcut makes select commands a no-op', () async {
    final root = Directory.systemTemp.createTempSync('pause-shortcut-');
    final shell = FakeShell();
    final container = ProviderContainer(
      overrides: [
        appShellProvider.overrideWithValue(shell),
        sessionImageStoreProvider.overrideWithValue(
          SessionImageStore(
            root: Directory('${root.path}/runtime')..createSync(),
          ),
        ),
        ocrWorkerProvider.overrideWithValue(ControlledWorker()),
      ],
    );
    addTearDown(() {
      container.dispose();
      root.deleteSync(recursive: true);
    });

    await AppLifecycle(container).start();
    container.read(shortcutPauseProvider.notifier).setPaused(true);

    await shell.handler!(AppCommand.select);

    expect(container.read(selectionOverlayProvider).phase, OverlayPhase.idle);
    expect(shell.events, isEmpty);
  });
}
