import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ubuntu_live_text/capture/capture_session.dart';
import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/picker/image_picker_port.dart';
import 'package:ubuntu_live_text/providers.dart';
import 'package:ubuntu_live_text/worker/ocr_worker.dart';

const _kLine = 'Fixture line for Live Text';

class _FakePicker implements ImagePickerPort {
  @override
  Future<String?> pickImagePath() async => '/tmp/sample.png';
}

class _FakeWorker implements OcrWorker {
  @override
  Future<OcrResult> recognize(String imagePath) async {
    return const OcrResult(
      imageWidth: 100,
      imageHeight: 80,
      fullText: _kLine,
      regions: [
        TextRegion(
          id: 'line-1',
          level: TextRegionLevel.line,
          text: _kLine,
          polygon: [
            Point(x: 10, y: 10),
            Point(x: 90, y: 10),
            Point(x: 90, y: 40),
            Point(x: 10, y: 40),
          ],
          confidence: 1,
          readingOrder: 0,
        ),
      ],
      timingsMs: TimingsMs(total: 0),
    );
  }

  @override
  Future<void> close() async {}
}

void main() {
  test('openImage reaches ready with injected adapters', () async {
    final container = ProviderContainer(
      overrides: [
        imagePickerProvider.overrideWithValue(_FakePicker()),
        ocrWorkerProvider.overrideWithValue(_FakeWorker()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(captureSessionProvider.notifier).openImage();

    final session = container.read(captureSessionProvider);
    expect(session.phase, CapturePhase.ready);
    expect(session.ocrResult?.fullText, _kLine);
  });
}
