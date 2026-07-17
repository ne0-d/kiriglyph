import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ubuntu_live_text/capture/capture_session.dart';
import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/picker/image_picker_port.dart';
import 'package:ubuntu_live_text/protocol/protocol_error.dart';
import 'package:ubuntu_live_text/providers.dart';
import 'package:ubuntu_live_text/worker/ocr_worker.dart';

const _kLine = 'Fixture line for Live Text';

class _FakePicker implements ImagePickerPort {
  @override
  Future<String?> pickImagePath() async => '/tmp/sample.png';
}

class _FakeWorker implements OcrWorker {
  @override
  Future<void> cancelActive() async {}

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
  Future<void> restart() async {}

  @override
  Future<void> close() async {}
}

class _SequencePicker implements ImagePickerPort {
  _SequencePicker(this.paths);

  final List<String?> paths;
  int _next = 0;

  @override
  Future<String?> pickImagePath() async => paths[_next++];
}

class _ControlledWorker implements OcrWorker {
  final requests = <String, Completer<OcrResult>>{};
  int cancelCalls = 0;
  int restartCalls = 0;

  @override
  Future<void> cancelActive() async {
    cancelCalls++;
  }

  @override
  Future<OcrResult> recognize(String imagePath) {
    return (requests[imagePath] = Completer<OcrResult>()).future;
  }

  @override
  Future<void> restart() async {
    restartCalls++;
  }

  @override
  Future<void> close() async {}
}

class _ErrorWorker implements OcrWorker {
  _ErrorWorker(this.error);

  final Object error;

  @override
  Future<void> cancelActive() async {}

  @override
  Future<OcrResult> recognize(String imagePath) async => throw error;

  @override
  Future<void> restart() async {}

  @override
  Future<void> close() async {}
}

class _RetryWorker implements OcrWorker {
  final events = <String>[];
  int _recognitions = 0;

  @override
  Future<void> cancelActive() async {}

  @override
  Future<OcrResult> recognize(String imagePath) async {
    events.add('recognize:$imagePath');
    if (_recognitions++ == 0) {
      throw const WorkerProcessError(
        kind: WorkerFailureKind.exited,
        message: 'worker exited',
      );
    }
    return _result('recovered');
  }

  @override
  Future<void> restart() async {
    events.add('restart');
  }

  @override
  Future<void> close() async {}
}

OcrResult _result(String text) => OcrResult(
  imageWidth: 100,
  imageHeight: 80,
  fullText: text,
  regions: const [],
  timingsMs: const TimingsMs(total: 0),
);

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

  test('a stale response cannot replace the active capture result', () async {
    final worker = _ControlledWorker();
    final container = ProviderContainer(
      overrides: [
        imagePickerProvider.overrideWithValue(
          _SequencePicker(['/tmp/first.png', '/tmp/second.png']),
        ),
        ocrWorkerProvider.overrideWithValue(worker),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(captureSessionProvider.notifier);
    final first = controller.openImage();
    await Future<void>.delayed(Duration.zero);
    final second = controller.openImage();
    await Future<void>.delayed(Duration.zero);

    worker.requests['/tmp/second.png']!.complete(_result('second'));
    await second;
    worker.requests['/tmp/first.png']!.complete(_result('first'));
    await first;

    final session = container.read(captureSessionProvider);
    expect(session.imagePath, '/tmp/second.png');
    expect(session.ocrResult?.fullText, 'second');
  });

  test(
    'cancelling recognition returns to idle and ignores completion',
    () async {
      final worker = _ControlledWorker();
      final container = ProviderContainer(
        overrides: [
          imagePickerProvider.overrideWithValue(
            _SequencePicker(['/tmp/cancel.png']),
          ),
          ocrWorkerProvider.overrideWithValue(worker),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(captureSessionProvider.notifier);
      final recognition = controller.openImage();
      await Future<void>.delayed(Duration.zero);

      await controller.cancelRecognition();
      expect(container.read(captureSessionProvider).phase, CapturePhase.idle);
      expect(worker.cancelCalls, 1);

      worker.requests['/tmp/cancel.png']!.complete(_result('too late'));
      await recognition;
      expect(container.read(captureSessionProvider).phase, CapturePhase.idle);
      expect(container.read(captureSessionProvider).ocrResult, isNull);
    },
  );

  test('worker and OCR failures have distinct safe outcomes', () async {
    final cases = <(Object, CaptureFailure, String)>[
      (
        const WorkerProcessError(
          kind: WorkerFailureKind.startup,
          message: 'secret startup detail',
        ),
        CaptureFailure.workerStartup,
        'The local OCR worker could not start. Try again.',
      ),
      (
        const WorkerProcessError(
          kind: WorkerFailureKind.exited,
          message: 'secret exit detail',
        ),
        CaptureFailure.workerExited,
        'The local OCR worker stopped unexpectedly. Try again.',
      ),
      (
        const WorkerProcessError(
          kind: WorkerFailureKind.timeout,
          message: 'secret timeout detail',
        ),
        CaptureFailure.timeout,
        'Text recognition took too long. Try again.',
      ),
      (
        const WorkerProcessError(
          kind: WorkerFailureKind.malformedResponse,
          message: 'secret protocol detail',
        ),
        CaptureFailure.malformedResponse,
        'The local OCR worker returned an invalid response. Try again.',
      ),
      (
        WorkerError(code: 'ocr_failed', message: 'engine details'),
        CaptureFailure.ocr,
        'Text recognition failed. Try another image.',
      ),
      (
        WorkerError(code: 'no_text', message: 'engine details'),
        CaptureFailure.noText,
        'No text was found in this image.',
      ),
      (
        WorkerError(code: 'image_unreadable', message: 'private path'),
        CaptureFailure.unsupportedInput,
        'This image could not be read. Choose a supported image file.',
      ),
    ];

    for (final (error, expectedFailure, expectedMessage) in cases) {
      final container = ProviderContainer(
        overrides: [
          imagePickerProvider.overrideWithValue(
            _SequencePicker(['/tmp/private.png']),
          ),
          ocrWorkerProvider.overrideWithValue(_ErrorWorker(error)),
        ],
      );

      await container.read(captureSessionProvider.notifier).openImage();
      final state = container.read(captureSessionProvider);

      expect(state.phase, CapturePhase.error);
      expect(state.failure, expectedFailure);
      expect(state.userMessage, expectedMessage);
      expect(state.userMessage, isNot(contains('secret')));
      expect(state.userMessage, isNot(contains('/tmp/')));
      container.dispose();
    }
  });

  test('retry restarts cleanly before recognizing the same image', () async {
    final worker = _RetryWorker();
    final container = ProviderContainer(
      overrides: [
        imagePickerProvider.overrideWithValue(
          _SequencePicker(['/tmp/retry.png']),
        ),
        ocrWorkerProvider.overrideWithValue(worker),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(captureSessionProvider.notifier);
    await controller.openImage();
    expect(container.read(captureSessionProvider).phase, CapturePhase.error);

    await controller.retry();

    final state = container.read(captureSessionProvider);
    expect(state.phase, CapturePhase.ready);
    expect(state.imagePath, '/tmp/retry.png');
    expect(state.ocrResult?.fullText, 'recovered');
    expect(worker.events, [
      'recognize:/tmp/retry.png',
      'restart',
      'recognize:/tmp/retry.png',
    ]);
  });
}
