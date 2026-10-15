import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:kiriglyph/ui/kiriglyph_app.dart';

import 'support/overlay_fakes.dart';
import 'support/workspace_harness.dart';

/// One line, "one two", on a frame the size of the 800x400 test window, so
/// frame pixels are window pixels.
OcrResult _displaySizedResult() {
  const text = 'one two';
  return OcrResult(
    imageWidth: 800,
    imageHeight: 400,
    fullText: text,
    regions: [
      box(
        'l1',
        text,
        0,
        100,
        100,
        240,
        130,
        ranges: [
          for (var index = 0; index < text.length; index++)
            character(
              index,
              text[index],
              100 + index * 20,
              100,
              120 + index * 20,
              130,
            ),
        ],
      ),
    ],
    timingsMs: const TimingsMs(total: 10),
  );
}

class _Overlay {
  _Overlay(this.shell, this.worker, this.container, this.started);

  final FakeShell shell;
  final ControlledWorker worker;
  final ProviderContainer container;
  final Future<bool> started;

  OverlayPhase get phase => container.read(selectionOverlayProvider).phase;
}

Future<void> _drawStroke(WidgetTester tester, List<Offset> points) async {
  final gesture = await tester.createGesture();
  await gesture.down(points.first);
  await tester.pump();
  for (final point in points.skip(1)) {
    await gesture.moveTo(point);
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

void main() {
  String? clipboardText;
  late Directory root;

  setUp(() {
    clipboardText = null;
    root = Directory.systemTemp.createTempSync('overlay-screen-');
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
    root.deleteSync(recursive: true);
  });

  /// Opens the overlay through the real controller with fake platform
  /// adapters. With [recognized] false, OCR stays in flight.
  Future<_Overlay> openOverlay(
    WidgetTester tester, {
    bool recognized = true,
    OcrResult? result,
  }) async {
    final ocr = result ?? sampleResult();
    final width = ocr.imageWidth;
    final height = ocr.imageHeight;
    final image = await tester.runAsync(
      () => createTestImage(width: width, height: height),
    );
    final pictures = Directory('${root.path}/Pictures')..createSync();
    final runtime = Directory('${root.path}/runtime')..createSync();
    final shell = FakeShell()
      ..placement = DisplayPlacement(
        monitors: [LogicalMonitor(x: 0, y: 0, width: width, height: height)],
        targetIndex: 0,
      );
    final worker = ControlledWorker(recognized ? ocr : null);
    await pumpApp(
      tester,
      size: const Size(800, 400),
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
          FakeFrameCodec(image!, width: width, height: height),
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
        () => recognized
            ? container.read(selectionOverlayProvider).phase ==
                  OverlayPhase.ready
            : worker.pending.isNotEmpty,
      );
    });
    await tester.pump();
    return _Overlay(shell, worker, container, started);
  }

  testWidgets('the overlay shows the frozen frame full bleed with a toolbar '
      'and no workspace chrome', (tester) async {
    await openOverlay(tester);

    final frame = tester.getRect(find.byKey(const Key('overlay-frame')));
    expect(frame, const Rect.fromLTWH(0, 0, 800, 400));
    expect(find.byKey(const Key('overlay-toolbar')), findsOneWidget);
    expect(find.text('Drag across text, or click an object'), findsOneWidget);
    expect(find.byKey(const Key('zoom-in')), findsNothing);
    expect(find.byKey(const Key('text-panel')), findsNothing);
    expect(find.text('Enable instant capture'), findsNothing);
  });

  testWidgets('Escape dismisses the overlay', (tester) async {
    final overlay = await openOverlay(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(overlay.phase, OverlayPhase.idle);
    expect(overlay.shell.events.last, 'hide');
    expect(find.byKey(const Key('overlay-toolbar')), findsNothing);
    expect(find.text('Enable instant capture'), findsOneWidget);
  });

  testWidgets('Close dismisses the overlay', (tester) async {
    final overlay = await openOverlay(tester);

    await tester.tap(find.byKey(const Key('overlay-close')));
    await tester.pump();

    expect(overlay.phase, OverlayPhase.idle);
    expect(overlay.shell.events.last, 'hide');
  });

  testWidgets('Copy all copies every line and confirms', (tester) async {
    await openOverlay(tester);

    await tester.tap(find.byKey(const Key('overlay-copy-all')));
    await tester.pump();

    expect(clipboardText, 'Alpha line\nBeta line\nGamma line');
    expect(find.text('Copied all 3 lines'), findsOneWidget);
  });

  testWidgets('Ctrl+A selects everything; Copy and Ctrl+C copy it', (
    tester,
  ) async {
    await openOverlay(tester);
    final copy = find.byKey(const Key('overlay-copy'));
    expect(tester.widget<ButtonStyleButton>(copy).onPressed, isNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    await tester.tap(copy);
    await tester.pump();
    expect(clipboardText, 'Alpha line\n\nBeta line\n\nGamma line');
    expect(find.text('Copied 3 lines'), findsOneWidget);

    clipboardText = null;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(clipboardText, 'Alpha line\n\nBeta line\n\nGamma line');
  });

  testWidgets('drag, double-click and triple-click select frozen pixels 1:1', (
    tester,
  ) async {
    await openOverlay(tester, result: _displaySizedResult());
    expect(
      tester.getRect(find.byKey(const Key('overlay-frame'))),
      const Rect.fromLTWH(0, 0, 800, 400),
    );

    Future<String?> copied() async {
      clipboardText = null;
      await tester.tap(find.byKey(const Key('overlay-copy')));
      await tester.pump();
      return clipboardText;
    }

    await tester.dragFrom(const Offset(125, 115), const Offset(70, 0));
    await tester.pump();
    expect(await copied(), 'ne t');

    await tester.pump(const Duration(seconds: 1));
    const word = Offset(210, 115);
    await tester.tapAt(word);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(word);
    await tester.pump(const Duration(milliseconds: 50));
    expect(await copied(), 'two');

    await tester.pump(const Duration(seconds: 1));
    for (var click = 0; click < 3; click++) {
      await tester.tapAt(word);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(await copied(), 'one two');
  });

  testWidgets('off-text stroke selects frozen full-bleed text', (tester) async {
    await openOverlay(tester, result: _displaySizedResult());

    await _drawStroke(tester, const [
      Offset(175, 90),
      Offset(250, 90),
      Offset(250, 140),
      Offset(175, 140),
      Offset(175, 90),
    ]);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(clipboardText, 'one two');
  });

  testWidgets('entry glow and scanning sweep run while recognizing', (
    tester,
  ) async {
    final overlay = await openOverlay(tester, recognized: false);

    expect(overlay.phase, OverlayPhase.recognizing);
    expect(find.text('Recognizing text…'), findsOneWidget);
    expect(find.byKey(const Key('overlay-entry-glow')), findsOneWidget);
    expect(find.byKey(const Key('overlay-scan-sweep')), findsOneWidget);

    overlay.worker.pending.single.complete(sampleResult());
    await tester.runAsync(() => overlay.started);
    await tester.pump();
    expect(find.byKey(const Key('overlay-scan-sweep')), findsNothing);

    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('reduced motion skips the glow and the sweep', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final overlay = await openOverlay(tester, recognized: false);

    expect(overlay.phase, OverlayPhase.recognizing);
    expect(find.text('Recognizing text…'), findsOneWidget);
    expect(find.byKey(const Key('overlay-entry-glow')), findsNothing);
    expect(find.byKey(const Key('overlay-scan-sweep')), findsNothing);
  });

  testWidgets('a permission notice is shown in onboarding', (tester) async {
    await pumpApp(
      tester,
      worker: FakeWorker([sampleResult()]),
      overrides: [appShellProvider.overrideWithValue(FakeShell())],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(KiriglyphApp)),
    );
    container.read(selectionNoticeProvider.notifier).show(permissionNotice);
    await tester.pump();

    expect(find.byKey(const Key('selection-notice')), findsOneWidget);
    expect(find.text('Enable instant capture'), findsOneWidget);
  });
}
