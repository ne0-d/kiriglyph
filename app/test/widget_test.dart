import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/background/shortcut_pause.dart';
import 'package:kiriglyph/capture/instant_capture.dart';
import 'package:kiriglyph/settings/app_settings.dart';
import 'package:kiriglyph/settings/folder_picker.dart';
import 'package:kiriglyph/shortcut/shortcut_service.dart';
import 'package:kiriglyph/ui/kiriglyph_app.dart';

import 'support/settings_fakes.dart';
import 'support/workspace_harness.dart';

void main() {
  String? clipboardText;

  setUp(() {
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboardText = (call.arguments as Map)['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return <String, dynamic>{'text': clipboardText};
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    FakeInstantCapture? instantCapture,
    FakeShortcutService? shortcuts,
    MemorySettingsStore? settings,
    FakeFolderPicker? folders,
    String? command,
    Size size = const Size(900, 900),
  }) async {
    await pumpApp(
      tester,
      instantCapture: instantCapture,
      selectionCommand: command,
      size: size,
      worker: FakeWorker([sampleResult()]),
      overrides: [
        if (shortcuts != null)
          shortcutServiceProvider.overrideWithValue(shortcuts),
        if (settings != null) settingsStoreProvider.overrideWithValue(settings),
        if (folders != null) folderPickerProvider.overrideWithValue(folders),
      ],
    );
    await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(KiriglyphApp)));

  /// Lets real file IO finish. The fake clock never completes it, and every
  /// IO step needs a pump before the next one starts, so alternate the two.
  Future<void> realIo(WidgetTester tester) async {
    for (var step = 0; step < 10; step++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  group('the page', () {
    testWidgets('is one native-style page with the main settings', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(find.text('Kiriglyph'), findsOneWidget);
      expect(
        find.text(
          'Press Ctrl+Super+T anywhere to select text or cut out an object.',
        ),
        findsOneWidget,
      );
      for (final title in const [
        'Capture',
        'Files',
        'Background',
        'Screen access',
        'Shortcut',
        'Save location',
        'Launch at login',
        'Pause shortcut',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      for (final key in const [
        'enable-instant-capture',
        'change-shortcut',
        'choose-save-folder',
        'launch-at-login',
        'pause-shortcut',
        'try-selection',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      // Quit lives in the native header bar's menu and the tray, not here.
      expect(find.byKey(const Key('quit-app')), findsNothing);
      expect(find.text('Quit'), findsNothing);
    });

    for (final size in const [
      Size(480, 400),
      Size(640, 300),
      Size(700, 500),
      Size(900, 600),
    ]) {
      testWidgets('does not overflow at ${size.width.toInt()}x'
          '${size.height.toInt()}', (tester) async {
        await pumpPage(tester, size: size);

        expect(find.byKey(const Key('enable-instant-capture')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the pause switch turns the shortcut off and on', (
      tester,
    ) async {
      await pumpPage(tester);
      expect(containerOf(tester).read(shortcutPauseProvider), isFalse);

      await tester.tap(find.byKey(const Key('pause-shortcut')));
      await tester.pump();
      expect(containerOf(tester).read(shortcutPauseProvider), isTrue);

      await tester.tap(find.text('Pause shortcut'));
      await tester.pump();
      expect(containerOf(tester).read(shortcutPauseProvider), isFalse);
    });
  });

  group('screen access', () {
    testWidgets('shows progress, then Allowed, and remembers it', (
      tester,
    ) async {
      final permission = Completer<InstantCaptureStatus>();
      final instantCapture = FakeInstantCapture(permission.future);
      final settings = MemorySettingsStore();
      await pumpPage(
        tester,
        instantCapture: instantCapture,
        settings: settings,
      );

      await tester.tap(find.byKey(const Key('enable-instant-capture')));
      await tester.pump();

      expect(instantCapture.calls, 1);
      expect(find.text('Requesting screen access…'), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const Key('enable-instant-capture')),
            )
            .onPressed,
        isNull,
      );

      permission.complete(InstantCaptureStatus.granted);
      await tester.pumpAndSettle();

      expect(find.text('Allowed. Captures run silently.'), findsOneWidget);
      expect(find.byKey(const Key('enable-instant-capture')), findsNothing);
      expect(settings.value.screenAccessGranted, isTrue);
    });

    testWidgets('shows Allowed on the next start without asking again', (
      tester,
    ) async {
      await pumpPage(
        tester,
        settings: MemorySettingsStore(
          const AppSettings(screenAccessGranted: true),
        ),
      );

      expect(find.text('Allowed. Captures run silently.'), findsOneWidget);
      expect(find.byKey(const Key('enable-instant-capture')), findsNothing);
    });

    testWidgets('explains a declined request and offers to try again', (
      tester,
    ) async {
      await pumpPage(
        tester,
        instantCapture: FakeInstantCapture(
          Future.value(InstantCaptureStatus.denied),
        ),
      );

      await tester.tap(find.byKey(const Key('enable-instant-capture')));
      await tester.pumpAndSettle();

      expect(find.textContaining('It was declined'), findsOneWidget);
      expect(
        find.textContaining('Settings → Apps → Kiriglyph'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('shortcut', () {
    testWidgets('is added for the user on the first run', (tester) async {
      final shortcuts = FakeShortcutService();
      final settings = MemorySettingsStore();
      await pumpPage(tester, shortcuts: shortcuts, settings: settings);

      expect(shortcuts.setCalls, [ctrlSuperT]);
      expect(find.text('Ctrl+Super+T, added for you'), findsOneWidget);
      expect(settings.value.shortcutAutoSetupDone, isTrue);
    });

    testWidgets('skips a candidate something else already uses', (
      tester,
    ) async {
      final shortcuts = FakeShortcutService(
        conflicts: {'<Control><Super>t': 'GNOME: something'},
      );
      await pumpPage(tester, shortcuts: shortcuts);

      expect(shortcuts.setCalls.single.toGtk(), '<Shift><Super>t');
      expect(find.text('Shift+Super+T, added for you'), findsOneWidget);
    });

    testWidgets('is not added again after the first run', (tester) async {
      final shortcuts = FakeShortcutService();
      await pumpPage(
        tester,
        shortcuts: shortcuts,
        settings: MemorySettingsStore(
          const AppSettings(shortcutAutoSetupDone: true),
        ),
      );

      expect(shortcuts.setCalls, isEmpty);
      expect(find.text('Not set'), findsOneWidget);
      expect(find.text('Set shortcut…'), findsOneWidget);
    });

    testWidgets('an existing shortcut is shown, not replaced', (tester) async {
      final shortcuts = FakeShortcutService.configured();
      await pumpPage(tester, shortcuts: shortcuts);

      expect(shortcuts.setCalls, isEmpty);
      expect(find.text('Ctrl+Super+T'), findsOneWidget);
      expect(find.text('Change…'), findsOneWidget);
    });

    testWidgets('falls back to the command when GNOME cannot be reached', (
      tester,
    ) async {
      final shortcuts = FakeShortcutService(
        currentFailure: const ShortcutException('gsettings is not available'),
      );
      await pumpPage(
        tester,
        shortcuts: shortcuts,
        command: 'kiriglyph --select --test',
      );

      expect(find.textContaining('could not set it for you'), findsOneWidget);
      expect(find.text('kiriglyph --select --test'), findsOneWidget);

      await tester.tap(find.byKey(const Key('copy-selection-command')));
      await tester.pump();

      expect(clipboardText, 'kiriglyph --select --test');
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    group('changing it', () {
      Future<void> chord(
        WidgetTester tester,
        List<LogicalKeyboardKey> modifiers,
        LogicalKeyboardKey key,
      ) async {
        for (final modifier in modifiers) {
          await tester.sendKeyDownEvent(modifier);
        }
        await tester.sendKeyDownEvent(key);
        await tester.sendKeyUpEvent(key);
        for (final modifier in modifiers.reversed) {
          await tester.sendKeyUpEvent(modifier);
        }
        await tester.pumpAndSettle();
      }

      testWidgets('records the keys, saves them, and updates the page', (
        tester,
      ) async {
        final shortcuts = FakeShortcutService.configured();
        await pumpPage(tester, shortcuts: shortcuts);

        await tester.tap(find.byKey(const Key('change-shortcut')));
        await tester.pumpAndSettle();
        expect(find.text('Waiting for keys…'), findsOneWidget);

        await chord(tester, [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.altLeft,
        ], LogicalKeyboardKey.keyJ);
        expect(find.text('Ctrl+Alt+J'), findsOneWidget);
        expect(find.byKey(const Key('shortcut-problem')), findsNothing);

        await tester.tap(find.byKey(const Key('shortcut-save')));
        await tester.pumpAndSettle();

        expect(shortcuts.setCalls.single.toGtk(), '<Control><Alt>j');
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Ctrl+Alt+J'), findsOneWidget);
        expect(
          find.text(
            'Press Ctrl+Alt+J anywhere to select text or cut out an object.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('refuses a shortcut something else already uses', (
        tester,
      ) async {
        final shortcuts = FakeShortcutService.configured()
          ..conflicts['<Control><Alt>k'] = 'GNOME Shell: toggle overview';
        await pumpPage(tester, shortcuts: shortcuts);
        await tester.tap(find.byKey(const Key('change-shortcut')));
        await tester.pumpAndSettle();

        await chord(tester, [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.altLeft,
        ], LogicalKeyboardKey.keyK);

        expect(
          find.textContaining('already used by GNOME Shell: toggle overview'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('shortcut-save')))
              .onPressed,
          isNull,
        );
        expect(shortcuts.setCalls, isEmpty);
      });

      testWidgets('refuses keys that would get in the way of typing', (
        tester,
      ) async {
        await pumpPage(tester, shortcuts: FakeShortcutService.configured());
        await tester.tap(find.byKey(const Key('change-shortcut')));
        await tester.pumpAndSettle();

        await chord(tester, [
          LogicalKeyboardKey.shiftLeft,
        ], LogicalKeyboardKey.keyA);

        expect(find.textContaining('get in the way of typing'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('shortcut-save')))
              .onPressed,
          isNull,
        );
      });

      testWidgets('Escape cancels without changing anything', (tester) async {
        final shortcuts = FakeShortcutService.configured();
        await pumpPage(tester, shortcuts: shortcuts);
        await tester.tap(find.byKey(const Key('change-shortcut')));
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(shortcuts.setCalls, isEmpty);
        expect(find.text('Ctrl+Super+T'), findsOneWidget);
      });

      testWidgets('shows why saving failed and stays open', (tester) async {
        final shortcuts = FakeShortcutService.configured()
          ..setFailure = const ShortcutException('write refused');
        await pumpPage(tester, shortcuts: shortcuts);
        await tester.tap(find.byKey(const Key('change-shortcut')));
        await tester.pumpAndSettle();
        await chord(tester, [
          LogicalKeyboardKey.controlLeft,
        ], LogicalKeyboardKey.keyJ);

        await tester.tap(find.byKey(const Key('shortcut-save')));
        await tester.pumpAndSettle();

        expect(find.textContaining('write refused'), findsOneWidget);
        expect(find.byType(AlertDialog), findsOneWidget);
      });
    });
  });

  group('save location', () {
    late Directory folder;

    setUp(
      () => folder = Directory.systemTemp.createTempSync('kiriglyph-pick-'),
    );
    tearDown(() => folder.deleteSync(recursive: true));

    testWidgets('choosing a folder saves it and shows it', (tester) async {
      final settings = MemorySettingsStore();
      final picker = FakeFolderPicker(folder.path);
      await pumpPage(tester, settings: settings, folders: picker);
      expect(find.byKey(const Key('reset-save-folder')), findsNothing);

      await tester.tap(find.byKey(const Key('choose-save-folder')));
      await realIo(tester);

      expect(picker.calls, 1);
      expect(settings.value.saveDirectory, folder.path);
      expect(find.text(folder.path), findsOneWidget);
      expect(find.byKey(const Key('reset-save-folder')), findsOneWidget);
    });

    testWidgets('Reset goes back to the default folder', (tester) async {
      final settings = MemorySettingsStore(
        AppSettings(saveDirectory: folder.path),
      );
      await pumpPage(tester, settings: settings);

      await tester.tap(find.byKey(const Key('reset-save-folder')));
      await tester.pumpAndSettle();

      expect(settings.value.saveDirectory, isNull);
      expect(find.byKey(const Key('reset-save-folder')), findsNothing);
    });

    testWidgets('a cancelled chooser changes nothing', (tester) async {
      final settings = MemorySettingsStore();
      await pumpPage(tester, settings: settings, folders: FakeFolderPicker());
      final before = settings.saves;

      await tester.tap(find.byKey(const Key('choose-save-folder')));
      await realIo(tester);

      expect(settings.saves, before);
      expect(settings.value.saveDirectory, isNull);
    });

    testWidgets('a folder it cannot write to is refused', (tester) async {
      final settings = MemorySettingsStore();
      await pumpPage(
        tester,
        settings: settings,
        folders: FakeFolderPicker('/proc/kiriglyph-cannot-write'),
      );

      await tester.tap(find.byKey(const Key('choose-save-folder')));
      await realIo(tester);

      expect(
        find.text('Kiriglyph cannot save files in that folder.'),
        findsOneWidget,
      );
      expect(settings.value.saveDirectory, isNull);
    });
  });
}
