import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/a11y/cursor_size.dart';
import 'package:kiriglyph/a11y/dual_stroke.dart';
import 'package:kiriglyph/a11y/keyboard_shortcuts.dart';
import 'package:kiriglyph/a11y/object_candidates.dart';
import 'package:kiriglyph/a11y/overlay_announcer.dart';
import 'package:kiriglyph/export/screenshot_export.dart';
import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/overlay/selection_overlay.dart';
import 'package:kiriglyph/providers.dart';
import 'package:kiriglyph/selection/region_selection.dart';
import 'package:kiriglyph/selection/region_selection_provider.dart';
import 'package:kiriglyph/theme/app_theme.dart';
import 'package:kiriglyph/ui/kiriglyph_app.dart';

import 'support/fake_subject_segmenter.dart';
import 'support/overlay_fakes.dart';
import 'support/workspace_harness.dart';

const _canvasKey = Key('capture-canvas-focus');
const _copyAllKey = Key('overlay-copy-all');
const _toolbarKey = Key('overlay-toolbar');
const _rectangleKey = Key('rectangle-selection-overlay');

/// Two lines on a 200 x 100 frame: "abcd" in the middle (inside the starter
/// rectangle) and "ef" near the bottom (outside it).
OcrResult _result() {
  TextRegion line(String id, String text, int order, double top) => box(
    id,
    text,
    order,
    60,
    top,
    140,
    top + 20,
    ranges: [
      for (var i = 0; i < text.length; i++)
        character(i, text[i], 60 + i * 20, top, 80 + i * 20, top + 20),
    ],
  );
  return resultWith([line('l1', 'abcd', 0, 40), line('l2', 'ef', 1, 70)]);
}

class _Clipboard implements ScreenshotClipboardPort {
  final copied = <Uint8List>[];

  @override
  Future<void> copyPng(Uint8List pngBytes) async => copied.add(pngBytes);
}

class _Codec implements ScreenshotImageCodec {
  @override
  Future<Uint8List> cropPng(Uint8List encodedPng, ScreenshotCrop crop) async =>
      Uint8List.fromList([crop.width, crop.height]);
}

double _contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  final light = x > y ? x : y;
  final dark = x > y ? y : x;
  return (light + 0.05) / (dark + 0.05);
}

void main() {
  late Directory root;
  late FakeOverlayAnnouncer announcer;
  late _Clipboard imageClipboard;
  String? clipboardText;

  setUp(() {
    clipboardText = null;
    announcer = FakeOverlayAnnouncer();
    imageClipboard = _Clipboard();
    root = Directory.systemTemp.createTempSync('overlay-keys-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboardText = (call.arguments as Map)['text'] as String?;
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    root.deleteSync(recursive: true);
  });

  Directory pictures() => Directory('${root.path}/out')..createSync();

  Future<ProviderContainer> open(
    WidgetTester tester, {
    OcrResult? result,
    Size size = const Size(1280, 800),
    List<Override> overrides = const [],
  }) async {
    final ocr = result ?? _result();
    await openOverlayCanvas(
      tester,
      testRoot: root,
      worker: ControlledWorker(ocr),
      result: ocr,
      size: size,
      overrides: [
        overlayAnnouncerProvider.overrideWithValue(announcer),
        subjectSegmenterProvider.overrideWithValue(FakeSubjectSegmenter()),
        screenshotExportControllerProvider.overrideWithValue(
          ScreenshotExportController(
            clipboard: imageClipboard,
            codec: _Codec(),
            clock: () => DateTime(2026, 1, 2, 3, 4, 5),
            picturesDirectory: () => pictures().path,
          ),
        ),
        ...overrides,
      ],
    );
    return ProviderScope.containerOf(tester.element(find.byType(KiriglyphApp)));
  }

  Future<void> chord(
    WidgetTester tester,
    List<LogicalKeyboardKey> modifiers,
    LogicalKeyboardKey key,
  ) async {
    for (final modifier in modifiers) {
      await tester.sendKeyDownEvent(modifier);
    }
    await tester.sendKeyEvent(key);
    for (final modifier in modifiers.reversed) {
      await tester.sendKeyUpEvent(modifier);
    }
    await tester.pump();
  }

  const ctrlKey = LogicalKeyboardKey.controlLeft;
  const shiftKey = LogicalKeyboardKey.shiftLeft;
  const altKey = LogicalKeyboardKey.altLeft;

  /// `?` is Shift+/ on a US keyboard; the simulator knows physical keys only.
  Future<void> questionMark(WidgetTester tester) =>
      chord(tester, [shiftKey], LogicalKeyboardKey.slash);

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  bool hasFocus(WidgetTester tester, Key key) {
    final primary = FocusManager.instance.primaryFocus?.context;
    if (primary == null) {
      return false;
    }
    return tester.any(
      find.descendant(
        of: find.byKey(key),
        matching: find.byElementPredicate((e) => identical(e, primary)),
        matchRoot: true,
      ),
    );
  }

  String selected(ProviderContainer c) =>
      c.read(regionSelectionProvider).selectedText;

  OverlayPhase phase(ProviderContainer c) =>
      c.read(selectionOverlayProvider).phase;

  /// Lets real file IO finish, pumping so the awaiting code resumes.
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'condition was not met');
  }

  group('help panel', () {
    testWidgets('? opens the cheat sheet and Escape closes it only', (
      tester,
    ) async {
      final c = await open(tester);

      await questionMark(tester);
      expect(find.byKey(const Key('keyboard-help-panel')), findsOneWidget);
      expect(hasFocus(tester, const Key('keyboard-help-close')), isTrue);

      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byKey(const Key('keyboard-help-panel')), findsNothing);
      expect(phase(c), OverlayPhase.ready);
      expect(hasFocus(tester, _canvasKey), isTrue);
    });

    testWidgets('Ctrl+? and F1 also open it', (tester) async {
      await open(tester);

      await chord(tester, [ctrlKey, shiftKey], LogicalKeyboardKey.slash);
      expect(find.byKey(const Key('keyboard-help-panel')), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byKey(const Key('keyboard-help-panel')), findsNothing);

      await press(tester, LogicalKeyboardKey.f1);
      expect(find.byKey(const Key('keyboard-help-panel')), findsOneWidget);
    });

    testWidgets('lists every shortcut and the pointer alternatives', (
      tester,
    ) async {
      await open(tester);
      await questionMark(tester);

      Finder inPanel(String text) => find.descendant(
        of: find.byKey(const Key('keyboard-help-panel')),
        matching: find.text(text),
      );
      for (final group in keyboardShortcutGroups) {
        expect(inPanel(group.title), findsOneWidget);
        for (final entry in group.entries) {
          expect(inPanel(entry.keys), findsWidgets, reason: entry.keys);
          expect(inPanel(entry.action), findsWidgets, reason: entry.action);
        }
      }
      expect(inPanel('Without a pointer'), findsOneWidget);
      for (final entry in pointerAlternatives) {
        expect(inPanel(entry.keys), findsOneWidget);
        expect(inPanel(entry.action), findsOneWidget);
      }
      // Every key the app documents is one of those below, kept in step by
      // the per-key tests in this file.
      final documented = [
        for (final g in keyboardShortcutGroups)
          for (final e in g.entries) e.keys,
      ];
      for (final key in const [
        'Ctrl+A',
        'Ctrl+C',
        'Ctrl+Shift+C',
        'Ctrl+S',
        'Ctrl+Shift+S',
        'Ctrl+Shift+F',
        'O / Shift+O',
        'R',
        'F6',
        'Escape',
        'Alt+Arrow keys',
        'Home / End',
        'Ctrl+Left / Ctrl+Right',
        'Ctrl+Shift+Up / Ctrl+Shift+Down',
      ]) {
        expect(documented, contains(key));
      }
    });

    testWidgets('the overlay ignores other keys while it is open', (
      tester,
    ) async {
      final c = await open(tester);
      await questionMark(tester);

      await chord(tester, [ctrlKey], LogicalKeyboardKey.keyA);

      expect(selected(c), isEmpty);
    });

    testWidgets('fits at 2.0x text on a 480 px display', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, size: const Size(480, 400));

      await questionMark(tester);

      expect(tester.takeException(), isNull);
      final panel = tester.getRect(
        find.byKey(const Key('keyboard-help-panel')),
      );
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(panel.right, lessThanOrEqualTo(480));
      expect(panel.bottom, lessThanOrEqualTo(400));
    });

    testWidgets('opening and closing are announced', (tester) async {
      await open(tester);
      await questionMark(tester);
      expect(announcer.last, contains('Keyboard shortcuts'));
      await press(tester, LogicalKeyboardKey.escape);
      expect(announcer.last, 'Keyboard shortcuts closed');
    });
  });

  group('text keys', () {
    testWidgets('arrows move the selection and Shift extends it', (
      tester,
    ) async {
      final c = await open(tester);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(selected(c), 'a');
      await chord(tester, [shiftKey], LogicalKeyboardKey.arrowRight);
      expect(selected(c), 'ab');
      await press(tester, LogicalKeyboardKey.arrowRight);
      // From the span 'ab' a plain Right selects the character after it.
      expect(selected(c), 'c');
    });

    testWidgets('Ctrl+arrows move by word and Shift extends', (tester) async {
      final c = await open(tester, result: wordCharacterResult());

      await chord(tester, [ctrlKey], LogicalKeyboardKey.arrowRight);
      expect(selected(c), 'one');
      await chord(tester, [ctrlKey], LogicalKeyboardKey.arrowRight);
      expect(selected(c), ',,');
      await chord(tester, [ctrlKey], LogicalKeyboardKey.arrowRight);
      expect(selected(c), 'two');
      await chord(tester, [ctrlKey], LogicalKeyboardKey.arrowLeft);
      expect(selected(c), ',,');
      await chord(tester, [ctrlKey, shiftKey], LogicalKeyboardKey.arrowRight);
      expect(selected(c), ',,  two');
    });

    testWidgets('Home and End move by line and Shift extends', (tester) async {
      final c = await open(tester, result: multilineCharacterResult());

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(selected(c), 'a');
      await press(tester, LogicalKeyboardKey.end);
      expect(selected(c), 'b');
      await press(tester, LogicalKeyboardKey.home);
      expect(selected(c), 'a');
      await chord(tester, [shiftKey], LogicalKeyboardKey.end);
      expect(selected(c), 'ab');
    });

    testWidgets('Ctrl+Shift+Down and Up select by paragraph', (tester) async {
      final c = await open(tester);

      await chord(tester, [ctrlKey, shiftKey], LogicalKeyboardKey.arrowDown);
      expect(selected(c), isNotEmpty);
      await chord(tester, [ctrlKey, shiftKey], LogicalKeyboardKey.arrowUp);
      expect(selected(c), isNotEmpty);
    });

    testWidgets('Ctrl+A selects all and Ctrl+C copies it', (tester) async {
      final c = await open(tester);

      await chord(tester, [ctrlKey], LogicalKeyboardKey.keyA);
      expect(selected(c), 'abcd\nef');
      await chord(tester, [ctrlKey], LogicalKeyboardKey.keyC);

      expect(clipboardText, 'abcd\nef');
      expect(announcer.last, startsWith('Copied'));
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('rectangle, save and copy keys', () {
    testWidgets('R starts a rectangle that selects the text inside it', (
      tester,
    ) async {
      final c = await open(tester);

      await press(tester, LogicalKeyboardKey.keyR);

      expect(find.byKey(_rectangleKey), findsOneWidget);
      expect(selected(c), 'abcd');
      expect(announcer.messages.join(' '), contains('Rectangle started'));
      expect(announcer.messages.join(' '), contains('Area selected'));
    });

    testWidgets('arrows resize, Alt+arrows move and R resets the rectangle', (
      tester,
    ) async {
      final c = await open(tester);
      await press(tester, LogicalKeyboardKey.keyR);
      expect(selected(c), 'abcd');

      // Alt+Down moves the rectangle 10 px down; arrow keys then resize it.
      await chord(tester, [altKey], LogicalKeyboardKey.arrowDown);
      await chord(tester, [altKey], LogicalKeyboardKey.arrowDown);
      await chord(tester, [altKey], LogicalKeyboardKey.arrowDown);
      expect(selected(c), 'ef');
      await press(tester, LogicalKeyboardKey.keyR);
      expect(selected(c), 'abcd\nef');
    });

    testWidgets('dragging a rectangle at the same points selects abcd', (
      tester,
    ) async {
      final c = await open(tester);
      final origin = tester.getTopLeft(find.byKey(_canvasKey));
      final gesture = await tester.startGesture(
        origin + const Offset(320, 240),
      );
      await gesture.moveTo(origin + const Offset(960, 560));
      await gesture.up();
      await tester.pump();
      expect(selected(c), 'abcd');
    });

    testWidgets('two clicks selects text like the keyboard rectangle', (
      tester,
    ) async {
      await open(tester);
      await press(tester, LogicalKeyboardKey.keyT);
      final origin = tester.getTopLeft(find.byKey(_canvasKey));
      Future<void> click(Offset offset) async {
        await tester.tapAt(origin + offset);
        await tester.pump();
      }

      await click(const Offset(320, 240));
      expect(
        announcer.messages.any(
          (message) => message.contains('First corner set'),
        ),
        isTrue,
      );
      await click(const Offset(960, 560));

      expect(announcer.messages, contains('Second corner set'));
      expect(
        announcer.messages.any(
          (message) => message.startsWith('Area selected'),
        ),
        isTrue,
      );
    });

    testWidgets(
      'R in free draw switches to the rectangle tool; T cycles tools',
      (tester) async {
        await open(tester);
        await tester.tap(find.text('Free draw'));
        await tester.pump();

        await press(tester, LogicalKeyboardKey.keyR);
        expect(announcer.last, startsWith('Rectangle tool'));

        await press(tester, LogicalKeyboardKey.keyT);
        expect(announcer.last, contains('Two clicks tool'));
        await press(tester, LogicalKeyboardKey.keyT);
        expect(announcer.last, 'Free draw tool');
        await press(tester, LogicalKeyboardKey.keyT);
        expect(announcer.last, startsWith('Rectangle tool'));
      },
    );

    testWidgets('Escape steps back: rectangle, then selection, then overlay', (
      tester,
    ) async {
      final c = await open(tester);
      await press(tester, LogicalKeyboardKey.keyR);
      expect(find.byKey(_rectangleKey), findsOneWidget);

      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byKey(_rectangleKey), findsNothing);
      expect(selected(c), 'abcd');
      expect(phase(c), OverlayPhase.ready);
      expect(announcer.last, 'Rectangle cleared');

      await press(tester, LogicalKeyboardKey.escape);
      expect(selected(c), isEmpty);
      expect(phase(c), OverlayPhase.ready);
      expect(announcer.last, 'Selection cleared');

      await press(tester, LogicalKeyboardKey.escape);
      expect(phase(c), OverlayPhase.idle);
      expect(announcer.last, 'Kiriglyph capture closed');
    });

    testWidgets('Ctrl+S saves the screenshot of the rectangle', (tester) async {
      await open(tester);
      await press(tester, LogicalKeyboardKey.keyR);

      await chord(tester, [ctrlKey], LogicalKeyboardKey.keyS);
      await waitFor(
        tester,
        () => announcer.messages.any((m) => m.startsWith('Saved')),
      );

      expect(announcer.last, 'Saved to Pictures/kiriglyph-20260102-030405.png');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Ctrl+Shift+S saves the area screenshot too', (tester) async {
      await open(tester);
      await press(tester, LogicalKeyboardKey.keyR);

      await chord(tester, [ctrlKey, shiftKey], LogicalKeyboardKey.keyS);
      await waitFor(
        tester,
        () => announcer.messages.any((m) => m.startsWith('Saved')),
      );

      expect(announcer.last, startsWith('Saved to Pictures/'));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Ctrl+Shift+F saves the full screenshot', (tester) async {
      await open(tester);

      await chord(tester, [ctrlKey, shiftKey], LogicalKeyboardKey.keyF);
      await waitFor(
        tester,
        () => announcer.messages.any((m) => m.startsWith('Saved')),
      );

      expect(
        announcer.last,
        'Saved full screenshot to Pictures/kiriglyph-20260102-030405.png',
      );
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Ctrl+Shift+C copies the selection as an image', (
      tester,
    ) async {
      await open(tester);
      await press(tester, LogicalKeyboardKey.keyR);

      await chord(tester, [ctrlKey, shiftKey], LogicalKeyboardKey.keyC);
      await waitFor(
        tester,
        () => announcer.messages.contains('Copied screenshot'),
      );
      expect(imageClipboard.copied, isNotEmpty);

      expect(announcer.last, 'Copied screenshot');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Ctrl+Shift+C without an area says so', (tester) async {
      await open(tester);

      await chord(tester, [ctrlKey, shiftKey], LogicalKeyboardKey.keyC);
      await waitFor(tester, () => announcer.assertiveMessages.isNotEmpty);

      expect(announcer.assertiveMessages, ['Select an area before copying.']);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('object keys', () {
    testWidgets('O and Shift+O cycle the object areas and say where', (
      tester,
    ) async {
      final c = await open(tester);
      final count = objectCandidates(
        imageWidth: 200,
        imageHeight: 100,
        regions: _result().regions,
      ).length;

      await press(tester, LogicalKeyboardKey.keyO);
      expect(find.byKey(const Key('object-keyboard-cursor')), findsOneWidget);
      expect(announcer.last, startsWith('Object 1 of $count, near top left'));

      await press(tester, LogicalKeyboardKey.keyO);
      expect(announcer.last, startsWith('Object 2 of $count'));

      await chord(tester, [shiftKey], LogicalKeyboardKey.keyO);
      expect(announcer.last, startsWith('Object 1 of $count'));
      await chord(tester, [shiftKey], LogicalKeyboardKey.keyO);
      expect(announcer.last, startsWith('Object $count of $count'));

      // Escape closes the cursor first; the overlay stays.
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byKey(const Key('object-keyboard-cursor')), findsNothing);
      expect(phase(c), OverlayPhase.ready);
    });
  });

  group('overlay keys', () {
    testWidgets('F6 moves focus between the canvas and the toolbar', (
      tester,
    ) async {
      await open(tester);
      expect(hasFocus(tester, _canvasKey), isTrue);

      await press(tester, LogicalKeyboardKey.f6);
      expect(hasFocus(tester, _copyAllKey), isTrue);
      expect(announcer.last, startsWith('Toolbar'));

      await press(tester, LogicalKeyboardKey.f6);
      expect(hasFocus(tester, _canvasKey), isTrue);
      expect(announcer.last, 'Canvas');
    });

    testWidgets('Alt+arrows move the focused toolbar and say so', (
      tester,
    ) async {
      // Test fonts are wide; leave room to move the toolbar.
      await open(tester, size: const Size(2400, 800));
      await press(tester, LogicalKeyboardKey.f6);
      await chord(tester, [altKey], LogicalKeyboardKey.arrowRight);
      await chord(tester, [altKey], LogicalKeyboardKey.arrowRight);
      final before = tester.getTopLeft(find.byKey(_toolbarKey));

      await chord(tester, [altKey], LogicalKeyboardKey.arrowLeft);

      final after = tester.getTopLeft(find.byKey(_toolbarKey));
      expect(after.dx, lessThan(before.dx));
      expect(announcer.last, 'Toolbar moved left');
    });

    testWidgets('the grip moves the toolbar with plain arrows once focused', (
      tester,
    ) async {
      // Test fonts are wide; leave room to move the toolbar.
      await open(tester, size: const Size(2400, 800));
      await press(tester, LogicalKeyboardKey.f6);
      await chord(tester, [altKey], LogicalKeyboardKey.arrowRight);
      await chord(tester, [altKey], LogicalKeyboardKey.arrowRight);
      final before = tester.getTopLeft(find.byKey(_toolbarKey));

      await tester.tap(find.byKey(const Key('overlay-toolbar-move-grip')));
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowLeft);

      expect(
        tester.getTopLeft(find.byKey(_toolbarKey)).dx,
        lessThan(before.dx),
      );
    });

    testWidgets('the Move toolbar menu is the pointer-free alternative', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.byKey(const Key('overlay-toolbar-move-menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Top'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(announcer.last, 'Toolbar moved to top');
    });
  });

  group('focus and targets', () {
    testWidgets('the canvas shows a focus ring for keyboard users', (
      tester,
    ) async {
      await open(tester);
      await press(tester, LogicalKeyboardKey.arrowRight);

      expect(find.byKey(const Key('canvas-focus-ring')), findsOneWidget);
    });

    testWidgets('toolbar controls are at least 24 px', (tester) async {
      await open(tester);

      for (final key in const [
        'overlay-copy',
        'overlay-copy-all',
        'overlay-close',
        'overlay-save-full-screenshot',
        'overlay-toolbar-move-grip-target',
        'overlay-toolbar-move-menu',
      ]) {
        final size = tester.getSize(find.byKey(Key(key)));
        expect(
          size.width,
          greaterThanOrEqualTo(AppA11y.minTapTarget),
          reason: key,
        );
        expect(
          size.height,
          greaterThanOrEqualTo(AppA11y.minTapTarget),
          reason: key,
        );
      }
    });

    testWidgets('selection chips are at least 24 px', (tester) async {
      await open(tester);
      await press(tester, LogicalKeyboardKey.keyR);

      for (final key in const [
        'selection-copy-text',
        'selection-lift-object',
        'selection-copy-screenshot',
        'selection-save-screenshot',
        'selection-search-web',
      ]) {
        final size = tester.getSize(find.byKey(Key(key)));
        expect(
          size.height,
          greaterThanOrEqualTo(AppA11y.minTapTarget),
          reason: key,
        );
        expect(
          size.width,
          greaterThanOrEqualTo(AppA11y.minTapTarget),
          reason: key,
        );
      }
    });

    for (final brightness in Brightness.values) {
      test('the focus ring is 2 px and 3:1 on the toolbar in $brightness', () {
        final theme = buildAppThemeForBrightness(brightness);
        final focused = theme.outlinedButtonTheme.style!.side!.resolve({
          WidgetState.focused,
        })!;
        expect(focused.width, 2);
        expect(focused.width, AppA11y.focusRingWidth);
        expect(
          _contrast(focused.color, theme.colorScheme.surfaceContainerLow),
          greaterThanOrEqualTo(3),
        );
      });
    }
  });

  group('colour independence and high contrast', () {
    testWidgets('the rectangle has a dark rim around a neon line', (
      tester,
    ) async {
      await open(tester);
      await press(tester, LogicalKeyboardKey.keyR);

      final render = tester.renderObject<RenderBox>(find.byKey(_rectangleKey));
      expect(
        render,
        paints
          ..path(style: PaintingStyle.stroke)
          ..path(
            color: dualStrokeDark.withValues(alpha: 0.6),
            style: PaintingStyle.stroke,
          )
          ..path(color: AppColors.neonMagenta, style: PaintingStyle.stroke),
      );
    });

    testWidgets('the object cursor has a dark rim around a light line', (
      tester,
    ) async {
      await open(tester);
      await press(tester, LogicalKeyboardKey.keyO);

      final render = tester.renderObject<RenderBox>(
        find.byKey(const Key('object-keyboard-cursor')),
      );
      expect(
        render,
        paints
          ..path(color: dualStrokeDark, style: PaintingStyle.stroke)
          ..path(color: dualStrokeLight, style: PaintingStyle.stroke),
      );
    });

    testWidgets('in high contrast the toolbar and chips are opaque with a '
        'solid 2 px border', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await open(tester);
      await press(tester, LogicalKeyboardKey.keyR);

      for (final key in const ['overlay-toolbar', 'selection-action-chip']) {
        final material = tester.widget<Material>(find.byKey(Key(key)));
        expect(material.color!.a, 1, reason: key);
        final shape = material.shape! as RoundedRectangleBorder;
        expect(shape.side.width, 2, reason: key);
        expect(shape.side.style, BorderStyle.solid, reason: key);
        expect(
          _contrast(shape.side.color, material.color!),
          greaterThanOrEqualTo(3),
          reason: key,
        );
      }
    });
  });

  group('GNOME cursor size', () {
    test('scales from the 24 default, within bounds, failing open', () {
      expect(cursorScaleFor(null), 1);
      expect(cursorScaleFor(0), 1);
      expect(cursorScaleFor(-5), 1);
      expect(cursorScaleFor(16), 1);
      expect(cursorScaleFor(24), 1);
      expect(cursorScaleFor(48), 2);
      expect(cursorScaleFor(64), closeTo(64 / 24, 1e-9));
      expect(cursorScaleFor(512), maxCursorScale);
    });

    test('the provider reads the port and fails open to 24', () async {
      Future<double> scaleWith(GnomeCursorSizePort port) async {
        final container = ProviderContainer(
          overrides: [gnomeCursorSizePortProvider.overrideWithValue(port)],
        );
        addTearDown(container.dispose);
        await container.read(gnomeCursorSizeProvider.future);
        return container.read(cursorScaleProvider);
      }

      expect(await scaleWith(FakeGnomeCursorSizePort(48)), 2);
      expect(await scaleWith(FakeGnomeCursorSizePort(null)), 1);
      expect(
        await scaleWith(FakeGnomeCursorSizePort(48, error: StateError('no'))),
        1,
      );
    });

    testWidgets('a large cursor scales the object cursor', (tester) async {
      await open(
        tester,
        overrides: [gnomeCursorSizeProvider.overrideWith((ref) async => 48)],
      );
      await tester.pump();
      await press(tester, LogicalKeyboardKey.keyO);

      final render = tester.renderObject<RenderBox>(
        find.byKey(const Key('object-keyboard-cursor')),
      );
      expect(
        render,
        paints..path(color: dualStrokeDark, style: PaintingStyle.stroke),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KiriglyphApp)),
      );
      expect(container.read(cursorScaleProvider), 2);
    });
  });

  group('announcer', () {
    testWidgets('the first message is sent at once and a burst is joined', (
      tester,
    ) async {
      final sent = <(String, bool)>[];
      final announcer = CoalescingAnnouncer(
        (message, assertive) => sent.add((message, assertive)),
      );

      announcer
        ..announce('One')
        ..announce('Two')
        ..announce('Three')
        ..announce('Three');
      expect(sent, [('One', false)]);

      await tester.pump(announcementCoalesceWindow);
      expect(sent.last, ('Two. Three', false));
      await tester.pump(announcementCoalesceWindow * 2);
      announcer.announce('Later');
      expect(sent.last, ('Later', false));
      announcer.dispose();
    });

    testWidgets('the same topic replaces a queued message', (tester) async {
      final sent = <String>[];
      final announcer = CoalescingAnnouncer((m, _) => sent.add(m));

      announcer
        ..announce('First')
        ..announce('1 line selected', topic: 'selection')
        ..announce('2 lines selected', topic: 'selection');
      await tester.pump(announcementCoalesceWindow);

      expect(sent, ['First', '2 lines selected']);
      announcer.dispose();
    });

    testWidgets('assertive and immediate messages skip the wait', (
      tester,
    ) async {
      final sent = <(String, bool)>[];
      final announcer = CoalescingAnnouncer((m, a) => sent.add((m, a)));

      announcer
        ..announce('Calm')
        ..announce('Queued')
        ..announce('Broken', assertive: true);
      expect(sent.last, ('Queued. Broken', true));

      announcer.announce('Bye', immediate: true);
      expect(sent.last, ('Bye', false));
      announcer.dispose();
    });

    testWidgets('empty messages are ignored', (tester) async {
      final sent = <String>[];
      final announcer = CoalescingAnnouncer((m, _) => sent.add(m));

      announcer.announce('   ');
      expect(sent, isEmpty);
    });
  });

  group('object candidates', () {
    test('skip areas mostly covered by text and describe the others', () {
      final all = objectCandidates(
        imageWidth: 300,
        imageHeight: 300,
        regions: const [],
      );
      expect(all, hasLength(9));
      expect(all.first.where, 'near top left');
      expect(all[1].where, 'near top');
      expect(all[4].where, 'near center');
      expect(all.last.where, 'near bottom right');

      final withText = objectCandidates(
        imageWidth: 300,
        imageHeight: 300,
        regions: [box('t', 'x', 0, 100, 100, 200, 200)],
      );
      expect(withText, hasLength(8));
      expect(withText.map((c) => c.where), isNot(contains('near center')));
    });

    test('fall back to every area when text covers all of them', () {
      final all = objectCandidates(
        imageWidth: 90,
        imageHeight: 90,
        regions: [box('t', 'x', 0, 0, 0, 90, 90)],
      );
      expect(all, hasLength(9));
    });

    test('the announcement and cycling wrap around', () {
      final candidates = objectCandidates(
        imageWidth: 90,
        imageHeight: 90,
        regions: const [],
      );
      expect(
        objectCandidateAnnouncement(1, candidates),
        'Object 2 of 9, near top',
      );
      expect(cycleObjectIndex(null, 5, forward: true), 0);
      expect(cycleObjectIndex(null, 5, forward: false), 4);
      expect(cycleObjectIndex(4, 5, forward: true), 0);
      expect(cycleObjectIndex(0, 5, forward: false), 4);
      expect(cycleObjectIndex(2, 0, forward: true), 0);
    });
  });

  group('word and line movement', () {
    RegionSelection selection(String text) =>
        RegionSelection([box('l1', text, 0, 0, 0, 10, 10)]);

    test('moveByWord walks words and punctuation runs, in both directions', () {
      var s = selection('one,,  two!');
      final seen = <String>[];
      for (var i = 0; i < 5; i++) {
        s = s.moveByWord(1, extend: false);
        seen.add(s.selectedText);
      }
      expect(seen, ['one', ',,', 'two', '!', '!']);
      s = s.moveByWord(-1, extend: false);
      expect(s.selectedText, 'two');
    });

    test('moveToLineEdge selects the edge character or extends to it', () {
      var s = selection('abc').moveHorizontal(1, extend: false);
      expect(s.selectedText, 'a');
      expect(s.moveToLineEdge(end: true, extend: false).selectedText, 'c');
      expect(s.moveToLineEdge(end: true, extend: true).selectedText, 'abc');
      s = selection('abc');
      expect(s.moveToLineEdge(end: false, extend: false).selectedText, 'a');
      expect(s.moveToLineEdge(end: true, extend: false).selectedText, 'c');
    });

    test('moveByWord crosses lines', () {
      final s = RegionSelection([
        box('a', 'one', 0, 0, 0, 10, 10),
        box('b', '  two', 1, 0, 20, 10, 30),
      ]);
      expect(
        s
            .moveByWord(1, extend: false)
            .moveByWord(1, extend: false)
            .selectedText,
        'two',
      );
    });
  });
}
