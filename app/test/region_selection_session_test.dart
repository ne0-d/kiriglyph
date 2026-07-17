import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ubuntu_live_text/capture/capture_session.dart';
import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/picker/image_picker_port.dart';
import 'package:ubuntu_live_text/providers.dart';
import 'package:ubuntu_live_text/selection/region_selection_provider.dart';
import 'package:ubuntu_live_text/worker/ocr_worker.dart';

class _Picker implements ImagePickerPort {
  @override
  Future<String?> pickImagePath() async => '/tmp/sample.png';
}

class _SequenceWorker implements OcrWorker {
  _SequenceWorker(this.results);

  final List<OcrResult> results;
  int _next = 0;

  @override
  Future<void> cancelActive() async {}

  @override
  Future<OcrResult> recognize(String imagePath) async =>
      results[_next++ % results.length];

  @override
  Future<void> restart() async {}

  @override
  Future<void> close() async {}
}

OcrResult _result(List<String> lines) => OcrResult(
  imageWidth: 100,
  imageHeight: 100,
  fullText: lines.join('\n'),
  regions: [
    for (var i = 0; i < lines.length; i++)
      TextRegion(
        id: 'line-$i',
        level: TextRegionLevel.line,
        text: lines[i],
        polygon: const [
          Point(x: 0, y: 0),
          Point(x: 10, y: 0),
          Point(x: 10, y: 10),
          Point(x: 0, y: 10),
        ],
        confidence: 1,
        readingOrder: i,
      ),
  ],
  timingsMs: const TimingsMs(total: 5),
);

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        imagePickerProvider.overrideWithValue(_Picker()),
        ocrWorkerProvider.overrideWithValue(
          _SequenceWorker([
            _result(['One', 'Two', 'Three']),
            _result(['Four', 'Five']),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    // Keep the selection alive across session transitions, as the UI does.
    container.listen(regionSelectionProvider, (_, _) {});
  });

  Future<void> openImage() =>
      container.read(captureSessionProvider.notifier).openImage();

  test(
    'a recognized session starts with the lines in order and no selection',
    () async {
      await openImage();

      final selection = container.read(regionSelectionProvider);
      expect(selection.allText, 'One\nTwo\nThree');
      expect(selection.hasSelection, isFalse);
    },
  );

  test('selection controller applies replace, extend and clear', () async {
    await openImage();
    final controller = container.read(regionSelectionProvider.notifier);

    controller.select('line-0');
    controller.extendTo('line-2');
    expect(
      container.read(regionSelectionProvider).selectedText,
      'One\nTwo\nThree',
    );

    controller.select('line-1');
    expect(container.read(regionSelectionProvider).selectedText, 'Two');

    controller.clear();
    expect(container.read(regionSelectionProvider).hasSelection, isFalse);
  });

  test('opening another image discards the previous selection', () async {
    await openImage();
    container.read(regionSelectionProvider.notifier).select('line-1');

    await openImage();

    final selection = container.read(regionSelectionProvider);
    expect(selection.allText, 'Four\nFive');
    expect(selection.hasSelection, isFalse);
  });

  test('starting a new image discards the previous selection', () async {
    await openImage();
    container.read(regionSelectionProvider.notifier).select('line-1');

    container.read(captureSessionProvider.notifier).reset();

    final selection = container.read(regionSelectionProvider);
    expect(selection.regions, isEmpty);
    expect(selection.hasSelection, isFalse);
    expect(container.read(captureSessionProvider).phase, CapturePhase.idle);
  });
}
