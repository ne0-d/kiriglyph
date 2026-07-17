import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/picker/image_picker_port.dart';
import 'package:ubuntu_live_text/providers.dart';
import 'package:ubuntu_live_text/ui/live_text_app.dart';
import 'package:ubuntu_live_text/worker/ocr_worker.dart';

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
  double b,
) => TextRegion(
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

class FakePicker implements ImagePickerPort {
  FakePicker({this.path = '/home/neo/Pictures/receipt.png'});

  String? path;
  int calls = 0;

  @override
  Future<String?> pickImagePath() async {
    calls++;
    return path;
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
  Future<void> restart() async {}

  @override
  Future<void> close() async {}
}

Future<void> pumpApp(
  WidgetTester tester, {
  FakePicker? picker,
  required OcrWorker worker,
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        imagePickerProvider.overrideWithValue(picker ?? FakePicker()),
        ocrWorkerProvider.overrideWithValue(worker),
      ],
      child: const LiveTextApp(),
    ),
  );
  await tester.pump();
}

Future<void> openImage(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-image-fab')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
