import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_live_text/picker/image_picker_port.dart';
import 'package:ubuntu_live_text/providers.dart';
import 'package:ubuntu_live_text/ui/live_text_app.dart';
import 'package:ubuntu_live_text/worker/ocr_worker.dart';
import 'package:ubuntu_live_text/ocr/ocr_result.dart';

/// Exercises the Open image control with injected picker/worker adapters.
void main() {
  testWidgets('tapping Open image uses injected picker and worker', (
    WidgetTester tester,
  ) async {
    var pickerCalls = 0;
    final picker = _CountingPicker(
      onPick: () => pickerCalls++,
      path: '/tmp/fixture.png',
    );
    var workerCalls = 0;
    final worker = _RecordingWorker(
      onRecognize: () => workerCalls++,
      result: const OcrResult(
        imageWidth: 4,
        imageHeight: 4,
        fullText: 'ok',
        regions: [
          TextRegion(
            id: 'line-1',
            level: TextRegionLevel.line,
            text: 'ok',
            polygon: [
              Point(x: 0, y: 0),
              Point(x: 4, y: 0),
              Point(x: 4, y: 4),
              Point(x: 0, y: 4),
            ],
            confidence: 1,
            readingOrder: 0,
          ),
        ],
        timingsMs: TimingsMs(total: 0),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imagePickerProvider.overrideWithValue(picker),
          ocrWorkerProvider.overrideWithValue(worker),
        ],
        child: const LiveTextApp(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('open-image-fab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(pickerCalls, 1);
    expect(workerCalls, 1);
    expect(find.text('Local OCR'), findsNothing);
    expect(find.byKey(const Key('ocr-region-line-1')), findsOneWidget);
    expect(find.text('ok'), findsWidgets);
  });
}

class _CountingPicker implements ImagePickerPort {
  _CountingPicker({required this.onPick, required this.path});

  final VoidCallback onPick;
  final String path;

  @override
  Future<String?> pickImagePath() async {
    onPick();
    return path;
  }
}

class _RecordingWorker implements OcrWorker {
  _RecordingWorker({required this.onRecognize, required this.result});

  final VoidCallback onRecognize;
  final OcrResult result;

  @override
  Future<OcrResult> recognize(String imagePath) async {
    onRecognize();
    return result;
  }

  @override
  Future<void> close() async {}
}
