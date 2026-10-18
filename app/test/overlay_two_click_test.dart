import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/a11y/overlay_announcer.dart';
import 'package:kiriglyph/export/screenshot_export.dart';
import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/providers.dart';
import 'package:kiriglyph/selection/rectangle_selection.dart';
import 'package:kiriglyph/ui/workspace/capture_canvas.dart';

import 'support/fake_subject_segmenter.dart';
import 'support/overlay_fakes.dart';
import 'support/workspace_harness.dart';

const _canvasFocusKey = Key('capture-canvas-focus');
const _markerKey = Key('two-click-corner-marker');

OcrResult _ocr() {
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

void main() {
  late Directory root;
  late FakeOverlayAnnouncer announcer;

  setUp(() {
    announcer = FakeOverlayAnnouncer();
    root = Directory.systemTemp.createTempSync('overlay-two-click-');
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<void> openOverlay(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    await openOverlayCanvas(
      tester,
      testRoot: root,
      worker: ControlledWorker(_ocr()),
      result: _ocr(),
      overrides: [
        overlayAnnouncerProvider.overrideWithValue(announcer),
        subjectSegmenterProvider.overrideWithValue(FakeSubjectSegmenter()),
        screenshotExportControllerProvider.overrideWithValue(
          ScreenshotExportController(
            clipboard: _NoopClipboard(),
            codec: _NoopCodec(),
            clock: () => DateTime(2026, 1, 2),
            picturesDirectory: () => root.path,
          ),
        ),
        ...overrides,
      ],
    );
  }

  Future<void> pressKey(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  Future<void> clickCanvas(WidgetTester tester, Offset offset) async {
    await tester.tapAt(offset);
    await tester.pump();
  }

  testWidgets('two-click tool announces corners and Escape cancels', (
    tester,
  ) async {
    await openOverlay(tester);
    await pressKey(tester, LogicalKeyboardKey.keyT);
    expect(announcer.last, contains('Two clicks tool'));

    final origin = tester.getTopLeft(find.byKey(_canvasFocusKey));
    await clickCanvas(tester, origin + const Offset(320, 240));
    expect(find.byKey(_markerKey), findsOneWidget);
    expect(announcer.last, contains('First corner set'));

    await pressKey(tester, LogicalKeyboardKey.escape);
    expect(find.byKey(_markerKey), findsNothing);
    expect(announcer.last, 'Two-click rectangle cancelled');
  });

  testWidgets('capture canvas two-click mode places a corner marker', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [overlayAnnouncerProvider.overrideWithValue(announcer)],
        child: MaterialApp(
          home: SizedBox(
            width: 1280,
            height: 800,
            child: CaptureCanvas.fullBleed(
              ocrResult: _ocr(),
              selectionTool: SelectionTool.twoClicks,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final origin = tester.getTopLeft(find.byKey(_canvasFocusKey));
    await clickCanvas(tester, origin + const Offset(400, 350));
    expect(find.byKey(_markerKey), findsOneWidget);
    expect(announcer.last, contains('First corner set'));
  });

  testWidgets('T cycles rectangle, two clicks, and free draw', (tester) async {
    await openOverlay(tester);

    await pressKey(tester, LogicalKeyboardKey.keyT);
    expect(announcer.last, contains('Two clicks tool'));

    await pressKey(tester, LogicalKeyboardKey.keyT);
    expect(announcer.last, 'Free draw tool');

    await pressKey(tester, LogicalKeyboardKey.keyT);
    expect(announcer.last, startsWith('Rectangle tool'));
  });
}

class _NoopClipboard implements ScreenshotClipboardPort {
  @override
  Future<void> copyPng(Uint8List pngBytes) async {}
}

class _NoopCodec implements ScreenshotImageCodec {
  @override
  Future<Uint8List> cropPng(Uint8List encodedPng, ScreenshotCrop crop) async =>
      encodedPng;
}
