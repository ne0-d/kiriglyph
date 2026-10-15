import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/capture/capture_session.dart';
import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/protocol/protocol_error.dart';
import 'package:kiriglyph/providers.dart';
import 'package:kiriglyph/worker/ocr_worker.dart';

class _CountingWorker implements OcrWorker {
  int cancelCalls = 0;

  @override
  Future<void> cancelActive() async => cancelCalls++;

  @override
  Future<OcrResult> recognize(String imagePath) => throw UnimplementedError();

  @override
  Future<void> restart() async {}

  @override
  Future<void> close() async {}
}

void main() {
  test('discardSession cancels the worker', () async {
    final worker = _CountingWorker();
    final container = ProviderContainer(
      overrides: [ocrWorkerProvider.overrideWithValue(worker)],
    );
    addTearDown(container.dispose);

    await container.read(captureSessionProvider.notifier).discardSession();
    expect(worker.cancelCalls, 1);
  });

  test('worker and OCR failures have distinct safe outcomes', () {
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
        'Text recognition failed. Try again.',
      ),
      (
        WorkerError(code: 'no_text', message: 'engine details'),
        CaptureFailure.noText,
        'No text was found in this image.',
      ),
      (
        WorkerError(code: 'image_unreadable', message: 'private path'),
        CaptureFailure.unsupportedInput,
        'This capture could not be read. Try the shortcut again.',
      ),
    ];

    for (final (error, expectedFailure, expectedMessage) in cases) {
      final outcome = recognitionFailureOf(error);
      expect(outcome.failure, expectedFailure);
      expect(outcome.message, expectedMessage);
      expect(outcome.message, isNot(contains('secret')));
      expect(outcome.message, isNot(contains('/tmp/')));
    }
  });
}
