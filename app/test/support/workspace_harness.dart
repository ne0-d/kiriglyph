import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/a11y/cursor_size.dart';
import 'package:kiriglyph/app/app_shell.dart';
import 'package:kiriglyph/capture/instant_capture.dart';
import 'package:kiriglyph/capture/screen_capture.dart';
import 'package:kiriglyph/capture/session_image_store.dart';
import 'package:kiriglyph/overlay/display_layout.dart';
import 'package:kiriglyph/overlay/overlay_frame.dart';
import 'package:kiriglyph/overlay/selection_overlay.dart';
import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/protocol/worker_protocol.dart';
import 'package:kiriglyph/providers.dart';
import 'package:kiriglyph/ui/kiriglyph_app.dart';
import 'package:kiriglyph/worker/ocr_worker.dart';

import 'overlay_fakes.dart';

/// Image used by workspace tests: 200 x 100 source pixels.
const kImageWidth = 200;
const kImageHeight = 100;

TextRegion box(
  String id,
  String text,
  int order,
  double l,
  double t,
  double r,
  double b, {
  List<TextCharacterRange> ranges = const [],
}) => TextRegion(
  id: id,
  level: TextRegionLevel.line,
  text: text,
  polygon: [
    Point(x: l, y: t),
    Point(x: r, y: t),
    Point(x: r, y: b),
    Point(x: l, y: b),
  ],
  confidence: 1,
  readingOrder: order,
  ranges: ranges,
);

TextCharacterRange character(
  int index,
  String text,
  double l,
  double t,
  double r,
  double b,
) => TextCharacterRange(
  start: index,
  end: index + 1,
  text: text,
  polygon: [
    Point(x: l, y: t),
    Point(x: r, y: t),
    Point(x: r, y: b),
    Point(x: l, y: b),
  ],
  geometryKind: text.trim().isEmpty
      ? CharacterGeometryKind.interpolatedGap
      : CharacterGeometryKind.derivedCtcPolygon,
  confidence: text.trim().isEmpty ? null : 1,
);

OcrResult characterSampleResult() => OcrResult(
  imageWidth: kImageWidth,
  imageHeight: kImageHeight,
  fullText: 'abcd',
  regions: [
    box(
      'l1',
      'abcd',
      0,
      20,
      10,
      100,
      30,
      ranges: [
        character(0, 'a', 20, 10, 40, 30),
        character(1, 'b', 40, 10, 60, 30),
        character(2, 'c', 60, 10, 80, 30),
        character(3, 'd', 80, 10, 100, 30),
      ],
    ),
  ],
  timingsMs: const TimingsMs(total: 10),
);

OcrResult wordCharacterResult() {
  const text = 'one,,  two!';
  return OcrResult(
    imageWidth: kImageWidth,
    imageHeight: kImageHeight,
    fullText: text,
    regions: [
      box(
        'l1',
        text,
        0,
        20,
        10,
        130,
        30,
        ranges: [
          for (var index = 0; index < text.length; index++)
            character(
              index,
              text[index],
              20 + index * 10,
              10,
              30 + index * 10,
              30,
            ),
        ],
      ),
    ],
    timingsMs: const TimingsMs(total: 10),
  );
}

OcrResult multilineCharacterResult() => OcrResult(
  imageWidth: kImageWidth,
  imageHeight: kImageHeight,
  fullText: 'ab\ncd',
  regions: [
    box(
      'l1',
      'ab',
      0,
      20,
      10,
      60,
      30,
      ranges: [
        character(0, 'a', 20, 10, 40, 30),
        character(1, 'b', 40, 10, 60, 30),
      ],
    ),
    box(
      'l2',
      'cd',
      1,
      20,
      40,
      60,
      60,
      ranges: [
        character(0, 'c', 20, 40, 40, 60),
        character(1, 'd', 40, 40, 60, 60),
      ],
    ),
  ],
  timingsMs: const TimingsMs(total: 10),
);

OcrResult sparseCharacterResult() => OcrResult(
  imageWidth: kImageWidth,
  imageHeight: kImageHeight,
  fullText: 'ab',
  regions: [
    box(
      'l1',
      'ab',
      0,
      20,
      10,
      100,
      30,
      ranges: [
        character(0, 'a', 20, 10, 40, 30),
        character(1, 'b', 80, 10, 100, 30),
      ],
    ),
  ],
  timingsMs: const TimingsMs(total: 10),
);

/// Three well separated lines plus one tiny speck, supplied out of reading
/// order so the tests also prove reading-order presentation.
OcrResult sampleResult() => OcrResult(
  imageWidth: kImageWidth,
  imageHeight: kImageHeight,
  fullText: 'ignored by the UI',
  regions: [
    box('l3', 'Gamma line', 2, 20, 70, 60, 85),
    box('l1', 'Alpha line', 0, 20, 10, 180, 25),
    box('l2', 'Beta line', 1, 20, 40, 120, 55),
  ],
  timingsMs: const TimingsMs(total: 420),
);

/// A sample-sized result carrying exactly [regions].
OcrResult resultWith(List<TextRegion> regions) => OcrResult(
  imageWidth: kImageWidth,
  imageHeight: kImageHeight,
  fullText: '',
  regions: regions,
  timingsMs: const TimingsMs(total: 420),
);

class FakeScreenCapture implements ScreenCapturePort {
  FakeScreenCapture([
    this.result = const ScreenCapture(
      ScreenCaptureStatus.captured,
      path: '/home/neo/Pictures/Screenshots/Screenshot.png',
    ),
  ]);

  ScreenCapture result;
  int calls = 0;

  @override
  Future<ScreenCapture> capture() async {
    calls++;
    return result;
  }

  @override
  Future<void> cancel() async {}
}

class FakeInstantCapture implements InstantCapturePort {
  FakeInstantCapture([Future<InstantCaptureStatus>? result])
    : result = result ?? Future.value(InstantCaptureStatus.granted);

  Future<InstantCaptureStatus> result;
  int calls = 0;

  @override
  Future<InstantCaptureStatus> requestPermission() {
    calls++;
    return result;
  }
}

class FakeWorker implements OcrWorker {
  FakeWorker(this.results);

  /// Each entry is returned in turn; an [Object] that is not an [OcrResult]
  /// is thrown instead.
  final List<Object> results;
  int calls = 0;

  @override
  Future<void> cancelActive() async {}

  @override
  Future<OcrResult> recognize(String imagePath) async {
    final next = results[calls++ % results.length];
    if (next is OcrResult) {
      return next;
    }
    throw next;
  }

  @override
  Future<List<DecodedCode>> decodeCodes(String imagePath) async =>
      throw UnimplementedError();

  @override
  Future<void> cancelInFlight() async {}

  @override
  Future<void> restart() async {}

  @override
  Future<void> close() async {}
}

Future<void> pumpApp(
  WidgetTester tester, {
  FakeScreenCapture? capture,
  FakeInstantCapture? instantCapture,
  String? selectionCommand,
  required OcrWorker worker,
  Size size = const Size(1280, 800),
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        screenCaptureProvider.overrideWithValue(capture ?? FakeScreenCapture()),
        instantCaptureProvider.overrideWithValue(
          instantCapture ?? FakeInstantCapture(),
        ),
        if (selectionCommand != null)
          selectionCommandProvider.overrideWithValue(selectionCommand),
        ocrWorkerProvider.overrideWithValue(worker),
        gnomeCursorSizePortProvider.overrideWithValue(
          FakeGnomeCursorSizePort(defaultCursorSize),
        ),
        ...overrides,
      ],
      child: const KiriglyphApp(),
    ),
  );
  await tester.pump();
}

/// Starts the selection overlay with a synthetic portal capture and fixture
/// OCR result, without a file picker.
Future<void> openOverlayCanvas(
  WidgetTester tester, {
  required Directory testRoot,
  required OcrWorker worker,
  OcrResult? result,
  Size size = const Size(1280, 800),
  List<Override> overrides = const [],
}) async {
  final ocr = result ?? sampleResult();
  final width = ocr.imageWidth;
  final height = ocr.imageHeight;
  final image = await tester.runAsync(
    () => createTestImage(width: width, height: height),
  );
  final pictures = Directory('${testRoot.path}/Pictures')..createSync();
  final runtime = Directory('${testRoot.path}/runtime')..createSync();
  final shell = FakeShell()
    ..placement = DisplayPlacement(
      monitors: [LogicalMonitor(x: 0, y: 0, width: width, height: height)],
      targetIndex: 0,
    );

  await pumpApp(
    tester,
    size: size,
    worker: worker,
    overrides: [
      appShellProvider.overrideWithValue(shell),
      silentScreenCaptureProvider.overrideWithValue(FakeSilentPortal(pictures)),
      sessionImageStoreProvider.overrideWithValue(
        SessionImageStore(root: runtime),
      ),
      overlayFrameCodecProvider.overrideWithValue(
        FakeFrameCodec(image!, width: width, height: height),
      ),
      ...overrides,
    ],
  );

  final app = find.byType(KiriglyphApp);
  expect(app, findsOneWidget);
  final container = ProviderScope.containerOf(tester.element(app));
  await tester.runAsync(() async {
    unawaited(container.read(selectionOverlayProvider.notifier).start());
    await until(
      () =>
          container.read(selectionOverlayProvider).phase == OverlayPhase.ready,
    );
  });
  await tester.pump();
}

/// Starts another overlay on an already-pumped app (after [openOverlayCanvas]).
Future<void> restartOverlayCanvas(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.runAsync(() async {
    unawaited(container.read(selectionOverlayProvider.notifier).start());
    await until(
      () =>
          container.read(selectionOverlayProvider).phase == OverlayPhase.ready,
    );
  });
  await tester.pump();
}
