import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/protocol/protocol_error.dart';
import 'package:kiriglyph/providers.dart';

enum CaptureFailure {
  captureUnavailable,
  captureDenied,
  captureFailed,
  captureInvalid,
  captureUnreadable,
  workerStartup,
  workerExited,
  timeout,
  malformedResponse,
  ocr,
  noText,
  unsupportedInput,
  unknown,
}

/// Resident setup-window session state. OCR runs in the selection overlay, not
/// here; this controller only coordinates worker cancellation on dismiss.
class CaptureSessionState {
  const CaptureSessionState();
}

class CaptureSessionController extends Notifier<CaptureSessionState> {
  @override
  CaptureSessionState build() => const CaptureSessionState();

  /// Always false; recognition happens in the overlay.
  bool get isBusy => false;

  /// Ends any in-flight overlay recognition and clears worker state.
  Future<void> discardSession() async {
    try {
      await ref.read(ocrWorkerProvider).cancelInFlight();
    } catch (_) {
      // Cancellation is best-effort when the overlay closes.
    }
  }

  Future<void> cancelRecognition() => discardSession();
}

/// The user-safe outcome of a failed recognition. Messages never include
/// worker details, paths, or recognized text.
({CaptureFailure failure, String message}) recognitionFailureOf(Object error) {
  if (error is WorkerProcessError) {
    return switch (error.kind) {
      WorkerFailureKind.startup => (
        failure: CaptureFailure.workerStartup,
        message: 'The local OCR worker could not start. Try again.',
      ),
      WorkerFailureKind.timeout => (
        failure: CaptureFailure.timeout,
        message: 'Text recognition took too long. Try again.',
      ),
      WorkerFailureKind.malformedResponse => (
        failure: CaptureFailure.malformedResponse,
        message:
            'The local OCR worker returned an invalid response. Try again.',
      ),
      WorkerFailureKind.exited ||
      WorkerFailureKind.cancelled ||
      WorkerFailureKind.closed => (
        failure: CaptureFailure.workerExited,
        message: 'The local OCR worker stopped unexpectedly. Try again.',
      ),
    };
  }
  if (error is ProtocolError) {
    return (
      failure: CaptureFailure.malformedResponse,
      message: 'The local OCR worker returned an invalid response. Try again.',
    );
  }
  if (error is WorkerError) {
    return switch (error.code) {
      'no_text' => (
        failure: CaptureFailure.noText,
        message: 'No text was found in this image.',
      ),
      'image_unreadable' => (
        failure: CaptureFailure.unsupportedInput,
        message: 'This capture could not be read. Try the shortcut again.',
      ),
      'ocr_failed' => (
        failure: CaptureFailure.ocr,
        message: 'Text recognition failed. Try again.',
      ),
      _ => (
        failure: CaptureFailure.unknown,
        message: 'Local OCR failed. Try again.',
      ),
    };
  }
  return (
    failure: CaptureFailure.unknown,
    message: 'Local OCR failed. Try again.',
  );
}

final captureSessionProvider =
    NotifierProvider<CaptureSessionController, CaptureSessionState>(
      CaptureSessionController.new,
    );
