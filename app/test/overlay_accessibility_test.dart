import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/app/app_shell.dart';
import 'package:kiriglyph/capture/session_image_store.dart';
import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/overlay/display_layout.dart';
import 'package:kiriglyph/overlay/overlay_frame.dart';
import 'package:kiriglyph/overlay/selection_overlay.dart';
import 'package:kiriglyph/providers.dart';
import 'package:kiriglyph/selection/region_selection_provider.dart';
import 'package:kiriglyph/ui/kiriglyph_app.dart';

import 'support/overlay_fakes.dart';
import 'support/workspace_harness.dart';

const _canvasKey = Key('capture-canvas-focus');
const _copyKey = Key('overlay-copy');
const _copyAllKey = Key('overlay-copy-all');
const _closeKey = Key('overlay-close');

/// Three paragraphs of one, two and one lines: "abcd\nefgh" is the first, so
/// paragraph keys have something to group. Supplied out of reading order.
OcrResult _paragraphResult() {
  TextRegion line(String id, String text, int order, double top) => box(
    id,
    text,
    order,
    20,
    top,
    100,
    top + 20,
    ranges: [
      for (var index = 0; index < text.length; index++)
        character(
          index,
          text[index],
          20 + index * 20,
          top,
          40 + index * 20,
          top + 20,
        ),
    ],
  );
  return resultWith([
    line('p2a', 'wxyz', 2, 80),
    line('p1b', 'efgh', 1, 35),
    line('p1a', 'abcd', 0, 10),
  ]);
}

class _Overlay {
  _Overlay(this.shell, this.worker, this.container, this.started);

  final FakeShell shell;
  final ControlledWorker worker;
  final ProviderContainer container;
  final Future<bool> started;

  OverlayPhase get phase => container.read(selectionOverlayProvider).phase;
}

void main() {
  String? clipboardText;
  late Directory root;
  late List<String> announcements;

  setUp(() {
    clipboardText = null;
    announcements = [];
    root = Directory.systemTemp.createTempSync('overlay-a11y-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            clipboardText = (call.arguments as Map)['text'] as String?;
            return null;
          case 'Clipboard.getData':
            return <String, dynamic>{'text': clipboardText};
          default:
            return null;
        }
      })
      ..setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
        message,
      ) async {
        final map = message as Map;
        if (map['type'] == 'announce') {
          announcements.add((map['data'] as Map)['message'] as String);
        }
        return null;
      });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.platform, null)
      ..setMockDecodedMessageHandler<dynamic>(
        SystemChannels.accessibility,
        null,
      );
    root.deleteSync(recursive: true);
  });

  void announcesOnThisPlatform(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(supportsAnnounce: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  /// Opens the overlay through the real controller with fake platform
  /// adapters. With [recognized] false OCR stays in flight; [until] decides
  /// when to stop waiting for the controller.
  Future<_Overlay> openOverlay(
    WidgetTester tester, {
    OcrResult? result,
    bool recognized = true,
    Object? error,
    OverlayPhase waitFor = OverlayPhase.ready,
    Size size = const Size(800, 400),
  }) async {
    final ocr = result ?? sampleResult();
    final image = await tester.runAsync(
      () => createTestImage(width: ocr.imageWidth, height: ocr.imageHeight),
    );
    final pictures = Directory('${root.path}/Pictures')..createSync();
    final runtime = Directory('${root.path}/runtime')..createSync();
    final shell = FakeShell()
      ..placement = DisplayPlacement(
        monitors: [
          LogicalMonitor(
            x: 0,
            y: 0,
            width: ocr.imageWidth,
            height: ocr.imageHeight,
          ),
        ],
        targetIndex: 0,
      );
    final worker = ControlledWorker(recognized ? ocr : null)..error = error;
    await pumpApp(
      tester,
      size: size,
      worker: worker,
      overrides: [
        appShellProvider.overrideWithValue(shell),
        silentScreenCaptureProvider.overrideWithValue(
          FakeSilentPortal(pictures),
        ),
        sessionImageStoreProvider.overrideWithValue(
          SessionImageStore(root: runtime),
        ),
        overlayFrameCodecProvider.overrideWithValue(
          FakeFrameCodec(
            image!,
            width: ocr.imageWidth,
            height: ocr.imageHeight,
          ),
        ),
      ],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(KiriglyphApp)),
    );
    late Future<bool> started;
    await tester.runAsync(() async {
      started = container.read(selectionOverlayProvider.notifier).start();
      await until(
        () => !recognized && error == null
            ? worker.pending.isNotEmpty
            : container.read(selectionOverlayProvider).phase == waitFor,
      );
    });
    await tester.pump();
    return _Overlay(shell, worker, container, started);
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

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) =>
      chord(tester, [LogicalKeyboardKey.controlLeft], key);

  Future<void> paragraphKey(WidgetTester tester, LogicalKeyboardKey key) =>
      chord(tester, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ], key);

  bool hasFocus(WidgetTester tester, Key key) {
    final primary = FocusManager.instance.primaryFocus?.context;
    if (primary == null) {
      return false;
    }
    final owner = find.byKey(key);
    return tester.any(
      find.descendant(
        of: owner,
        matching: find.byElementPredicate((e) => identical(e, primary)),
        matchRoot: true,
      ),
    );
  }

  String? selectedText(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(KiriglyphApp)))
          .read(regionSelectionProvider)
          .selectedText;

  group('keyboard focus', () {
    testWidgets('arrows and Ctrl+C work on open without a click', (
      tester,
    ) async {
      await openOverlay(tester, result: _paragraphResult());

      expect(hasFocus(tester, _canvasKey), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(selectedText(tester), 'a');
      await ctrl(tester, LogicalKeyboardKey.keyC);
      expect(clipboardText, 'a');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Escape works before text is ready', (tester) async {
      final overlay = await openOverlay(tester, recognized: false);

      expect(overlay.phase, OverlayPhase.recognizing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(overlay.phase, OverlayPhase.idle);
    });

    testWidgets('Escape and Ctrl+C work while a toolbar button has focus', (
      tester,
    ) async {
      final overlay = await openOverlay(tester, result: _paragraphResult());
      await ctrl(tester, LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(hasFocus(tester, _copyKey), isTrue);

      await ctrl(tester, LogicalKeyboardKey.keyC);
      expect(clipboardText, 'abcd\nefgh\n\nwxyz');
      await tester.pump(const Duration(seconds: 3));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(overlay.phase, OverlayPhase.idle);
    });
  });

  group('tab order', () {
    testWidgets('visits the canvas, Copy, Copy all, then Close, and wraps', (
      tester,
    ) async {
      await openOverlay(tester, result: _paragraphResult());
      await ctrl(tester, LogicalKeyboardKey.keyA);

      Future<void> tab([bool back = false]) async {
        if (back) {
          await chord(tester, [
            LogicalKeyboardKey.shiftLeft,
          ], LogicalKeyboardKey.tab);
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
      }

      expect(hasFocus(tester, _canvasKey), isTrue);
      await tab();
      expect(hasFocus(tester, _copyKey), isTrue);
      await tab();
      expect(hasFocus(tester, _copyAllKey), isTrue);
      await tab();
      expect(hasFocus(tester, _closeKey), isTrue);
      await tab();
      expect(hasFocus(tester, _canvasKey), isTrue);
      await tab(true);
      expect(hasFocus(tester, _closeKey), isTrue);
    });

    testWidgets('recognized lines are not tab stops', (tester) async {
      await openOverlay(tester, result: sampleResult());
      // Without a selection Copy is disabled: canvas, Copy all, Close.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(hasFocus(tester, _copyAllKey), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(hasFocus(tester, _closeKey), isTrue);
    });

    testWidgets('Space on Close dismisses, returning to the previous app', (
      tester,
    ) async {
      final overlay = await openOverlay(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(hasFocus(tester, _closeKey), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(overlay.phase, OverlayPhase.idle);
      expect(overlay.shell.events.last, 'hide');
    });
  });

  group('paragraph selection by keyboard', () {
    Future<String?> copied(WidgetTester tester) async {
      clipboardText = null;
      await tester.tap(find.byKey(_copyKey));
      await tester.pump();
      return clipboardText;
    }

    testWidgets('Ctrl+Shift+Down selects paragraphs from the top, one at a '
        'time', (tester) async {
      await openOverlay(tester, result: _paragraphResult());

      await paragraphKey(tester, LogicalKeyboardKey.arrowDown);
      expect(await copied(tester), 'abcd\nefgh');
      await tester.pump(const Duration(seconds: 3));

      await paragraphKey(tester, LogicalKeyboardKey.arrowDown);
      expect(await copied(tester), 'abcd\nefgh\n\nwxyz');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Ctrl+Shift+Up selects from the bottom', (tester) async {
      await openOverlay(tester, result: _paragraphResult());

      await paragraphKey(tester, LogicalKeyboardKey.arrowUp);
      expect(await copied(tester), 'wxyz');
      await tester.pump(const Duration(seconds: 3));

      await paragraphKey(tester, LogicalKeyboardKey.arrowUp);
      expect(await copied(tester), 'abcd\nefgh\n\nwxyz');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('plain arrows still move by character', (tester) async {
      await openOverlay(tester, result: _paragraphResult());
      await paragraphKey(tester, LogicalKeyboardKey.arrowDown);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      // From the end of the selected paragraphs: the next character.
      expect(selectedText(tester), 'w');
    });

    testWidgets('the toolbar tooltips show the keys', (tester) async {
      await openOverlay(tester, result: _paragraphResult());

      // Copy buttons sit inside a Tooltip; IconButton builds its own.
      String tip(Key key) {
        final around = find.ancestor(
          of: find.byKey(key),
          matching: find.byType(Tooltip),
        );
        final inside = find.descendant(
          of: find.byKey(key),
          matching: find.byType(Tooltip),
        );
        return tester
            .widget<Tooltip>(tester.any(around) ? around.first : inside.first)
            .message!;
      }

      expect(tip(_copyKey), contains('Ctrl+C'));
      expect(tip(_copyKey), contains('Ctrl+Shift+Down'));
      expect(tip(_copyKey), contains('Ctrl+Shift+Up'));
      expect(tip(_copyAllKey), contains('Ctrl+A'));
      expect(tip(_closeKey), contains('Esc'));
    });
  });

  group('semantics', () {
    /// Labels of every semantics node below [parent], depth first, in the
    /// order a screen reader visits them.
    List<SemanticsNode> traverse(SemanticsNode parent) => [
      for (final child in parent.debugListChildrenInOrder(
        DebugSemanticsDumpOrder.traversalOrder,
      )) ...[child, ...traverse(child)],
    ];

    // The Focus around the canvas adds a node of its own; the canvas
    // description is the Semantics widget inside it.
    final canvasNode = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'Recognized text',
    );

    List<SemanticsNode> nodes(WidgetTester tester) {
      var root = tester.getSemantics(canvasNode);
      while (root.parent != null) {
        root = root.parent!;
      }
      return traverse(root);
    }

    testWidgets('recognized lines are exposed top to bottom', (tester) async {
      final handle = tester.ensureSemantics();
      // sampleResult supplies lines out of reading order and with different
      // sizes, so neither paint order nor size order matches.
      await openOverlay(tester);

      final lines = [
        for (final node in nodes(tester))
          if (node.label.startsWith('Line ')) node.label,
      ];
      expect(lines, [
        'Line 1: Alpha line',
        'Line 2: Beta line',
        'Line 3: Gamma line',
      ]);
      handle.dispose();
    });

    testWidgets('selection is exposed on the lines and on the canvas', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await openOverlay(tester);
      bool selected(String id) =>
          tester
              .getSemantics(find.byKey(Key('ocr-region-$id')))
              .flagsCollection
              .isSelected ==
          Tristate.isTrue;

      await tester.tap(find.byKey(const Key('ocr-region-l2')));
      await tester.pump();

      expect(selected('l2'), isTrue);
      expect(selected('l1'), isFalse);
      final canvas = tester.getSemantics(canvasNode);
      expect(canvas.value, contains('selected'));
      expect(canvas.value, isNot('No text selected'));
      handle.dispose();
    });

    testWidgets('the canvas is described once and the frozen frame is '
        'silent', (tester) async {
      final handle = tester.ensureSemantics();
      await openOverlay(tester);

      final canvas = tester.getSemantics(canvasNode);
      expect(canvas.label, 'Recognized text');
      expect(canvas.hint, contains('Arrow keys'));
      expect(canvas.hint, contains('Ctrl+Shift+Down'));
      final labels = [for (final node in nodes(tester)) node.label];
      expect(labels.where((l) => l.toLowerCase().contains('image')), isEmpty);
      expect(
        nodes(tester).where((node) => node.label.contains('Character')),
        isEmpty,
        reason: 'per-line boilerplate is gone',
      );
      handle.dispose();
    });

    testWidgets('recognized text is never inside a live region', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await openOverlay(tester);
      await tester.tap(find.byKey(_copyAllKey));
      await tester.pump();

      for (final node in nodes(tester)) {
        if (node.flagsCollection.isLiveRegion) {
          expect(node.label, isNot(contains('Alpha')));
          expect(node.label, isNot(contains('Gamma')));
        }
      }
      await tester.pump(const Duration(seconds: 3));
      handle.dispose();
    });
  });

  group('announcements', () {
    testWidgets('recognizing, ready and copied are announced briefly', (
      tester,
    ) async {
      announcesOnThisPlatform(tester);
      final overlay = await openOverlay(tester, recognized: false);
      expect(announcements, ['Recognizing text…']);

      overlay.worker.pending.single.complete(sampleResult());
      await tester.runAsync(() => overlay.started);
      await tester.pump();
      expect(announcements.last, '3 lines found');

      await tester.tap(find.byKey(_copyAllKey));
      await tester.pump();
      expect(announcements.last, 'Copied all 3 lines');

      expect(
        announcements.join(' '),
        isNot(anyOf(contains('Alpha'), contains('Beta'), contains('Gamma'))),
      );
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('no text found is announced without closing', (tester) async {
      announcesOnThisPlatform(tester);
      await openOverlay(
        tester,
        result: resultWith(const []),
        waitFor: OverlayPhase.ready,
      );

      expect(
        announcements.last,
        'No text found - click or draw around an object',
      );
      expect(
        find.text('No text found - click or draw around an object'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const Key('overlay-toolbar')), findsOneWidget);
    });

    testWidgets('an OCR failure is announced', (tester) async {
      announcesOnThisPlatform(tester);
      await openOverlay(
        tester,
        recognized: false,
        error: Exception('boom'),
        waitFor: OverlayPhase.failed,
      );

      expect(announcements, hasLength(1));
      final message = announcements.last;
      expect(find.text(message), findsOneWidget);
      expect(message, isNot(contains('boom')));
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a copy failure is announced', (tester) async {
      announcesOnThisPlatform(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'unavailable');
          }
          return null;
        },
      );
      await openOverlay(tester);

      await tester.tap(find.byKey(_copyAllKey));
      await tester.pump();

      expect(announcements.last, 'Could not copy. Try again.');
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('selecting never announces; hint and count stay silent', (
      tester,
    ) async {
      announcesOnThisPlatform(tester);
      await openOverlay(tester);
      final before = announcements.length;

      await paragraphKey(tester, LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(announcements.length, before);
    });

    testWidgets('where announcing is unsupported, a live region carries '
        'the state instead', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final handle = tester.ensureSemantics();
      final overlay = await openOverlay(tester, recognized: false);
      expect(announcements, isEmpty);
      expect(
        tester
            .getSemantics(find.text('Recognizing text…'))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );

      overlay.worker.pending.single.complete(sampleResult());
      await tester.runAsync(() => overlay.started);
      await tester.pump();
      // The idle hint is not a state change worth interrupting for.
      expect(
        tester
            .getSemantics(find.text('Drag across text, or click an object'))
            .flagsCollection
            .isLiveRegion,
        isFalse,
      );
      handle.dispose();
    });

    testWidgets('where announcing is supported, the status is not also a '
        'live region', (tester) async {
      announcesOnThisPlatform(tester);
      final handle = tester.ensureSemantics();
      await openOverlay(tester, recognized: false);

      expect(
        tester
            .getSemantics(find.text('Recognizing text…'))
            .flagsCollection
            .isLiveRegion,
        isFalse,
      );
      handle.dispose();
    });
  });

  group('legibility', () {
    double contrast(Color foreground, Color background) {
      final opaque = Color.alphaBlend(foreground, background);
      final a = opaque.computeLuminance();
      final b = background.computeLuminance();
      final light = a > b ? a : b;
      final dark = a > b ? b : a;
      return (light + 0.05) / (dark + 0.05);
    }

    for (final (name, brightness, highContrast) in const [
      ('light', Brightness.light, false),
      ('dark', Brightness.dark, false),
      ('light high contrast', Brightness.light, true),
      ('dark high contrast', Brightness.dark, true),
    ]) {
      testWidgets('status text keeps 4.5:1 contrast in $name', (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(highContrast: highContrast);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await openOverlay(tester);

        final status = tester.widget<Text>(
          find.byKey(const Key('overlay-status')),
        );
        final surface = tester
            .widget<Material>(find.byKey(const Key('overlay-toolbar')))
            .color!;
        final color = status.style!.color!;
        expect(
          contrast(color, surface),
          greaterThanOrEqualTo(highContrast ? 7.0 : 4.5),
        );
      });
    }

    for (final size in const [Size(800, 400), Size(480, 400)]) {
      testWidgets('toolbar fits at 2.0x text on ${size.width.toInt()} px', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await openOverlay(tester, size: size);

        expect(tester.takeException(), isNull);
        final toolbar = tester.getRect(
          find.byKey(const Key('overlay-toolbar')),
        );
        bool inside(Rect rect) =>
            rect.left >= 0 &&
            rect.top >= 0 &&
            rect.right <= size.width &&
            rect.bottom <= size.height;
        expect(inside(toolbar), isTrue, reason: '$toolbar in $size');
        for (final key in [_copyAllKey, _closeKey]) {
          final rect = tester.getRect(find.byKey(key));
          expect(inside(rect), isTrue, reason: '$key $rect in $size');
        }
      });
    }

    testWidgets('a long failure message is shown whole at 2.0x text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openOverlay(
        tester,
        recognized: false,
        error: Exception('boom'),
        waitFor: OverlayPhase.failed,
      );

      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.byKey(const Key('overlay-status')));
      expect(text.maxLines, isNull);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('selection has a text cue and an outline, not only a tint', (
      tester,
    ) async {
      await openOverlay(tester, result: _paragraphResult());
      expect(find.text('Drag across text, or click an object'), findsOneWidget);

      await paragraphKey(tester, LogicalKeyboardKey.arrowDown);

      expect(find.text('2 lines selected'), findsOneWidget);
      final painted = find.descendant(
        of: find.byKey(const Key('ocr-character-line-p1a')),
        matching: find.byType(CustomPaint),
      );
      final render = tester.renderObject<RenderBox>(painted.first);
      expect(
        render,
        paints
          ..path(style: PaintingStyle.fill)
          ..path(style: PaintingStyle.stroke),
      );
    });

    testWidgets('the recognizing state is text, with motion optional', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await openOverlay(tester, recognized: false);

      expect(find.text('Recognizing text…'), findsOneWidget);
      expect(find.byKey(const Key('overlay-scan-sweep')), findsNothing);
    });
  });
}
