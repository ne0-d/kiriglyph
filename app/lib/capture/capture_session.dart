import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/protocol/protocol_error.dart';
import 'package:ubuntu_live_text/providers.dart';

enum CapturePhase { idle, recognizing, ready, error }

enum CaptureFailure {
  workerStartup,
  workerExited,
  timeout,
  malformedResponse,
  ocr,
  noText,
  unsupportedInput,
  unknown,
}

class CaptureSessionState {
  const CaptureSessionState({
    this.phase = CapturePhase.idle,
    this.imagePath,
    this.ocrResult,
    this.userMessage,
    this.failure,
  });

  final CapturePhase phase;
  final String? imagePath;
  final OcrResult? ocrResult;
  final String? userMessage;
  final CaptureFailure? failure;

  CaptureSessionState copyWith({
    CapturePhase? phase,
    String? imagePath,
    OcrResult? ocrResult,
    String? userMessage,
    CaptureFailure? failure,
    bool clearImagePath = false,
    bool clearOcrResult = false,
    bool clearUserMessage = false,
    bool clearFailure = false,
  }) {
    return CaptureSessionState(
      phase: phase ?? this.phase,
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
      ocrResult: clearOcrResult ? null : (ocrResult ?? this.ocrResult),
      userMessage: clearUserMessage ? null : (userMessage ?? this.userMessage),
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

class CaptureSessionController extends Notifier<CaptureSessionState> {
  int _operation = 0;

  @override
  CaptureSessionState build() => const CaptureSessionState();

  Future<void> openImage() async {
    final operation = ++_operation;
    final picker = ref.read(imagePickerProvider);
    final path = await picker.pickImagePath();
    if (path == null || operation != _operation) {
      return;
    }
    await _recognizePath(path, operation: operation);
  }

  Future<void> retry() async {
    final path = state.imagePath;
    if (path == null) {
      return;
    }
    final operation = ++_operation;
    await _recognizePath(path, operation: operation, restart: true);
  }

  Future<void> _recognizePath(
    String path, {
    required int operation,
    bool restart = false,
  }) async {
    state = state.copyWith(
      phase: CapturePhase.recognizing,
      imagePath: path,
      clearOcrResult: true,
      clearUserMessage: true,
      clearFailure: true,
    );

    try {
      final worker = ref.read(ocrWorkerProvider);
      if (restart) {
        await worker.restart();
        if (operation != _operation) {
          return;
        }
      }
      final result = await worker.recognize(path);
      if (operation != _operation) {
        return;
      }
      state = state.copyWith(
        phase: CapturePhase.ready,
        ocrResult: result,
        clearUserMessage: true,
        clearFailure: true,
      );
    } catch (error) {
      if (operation != _operation) {
        return;
      }
      final outcome = _captureFailure(error);
      state = state.copyWith(
        phase: CapturePhase.error,
        userMessage: outcome.message,
        failure: outcome.failure,
        clearOcrResult: true,
      );
    }
  }

  Future<void> cancelRecognition() async {
    _operation++;
    state = const CaptureSessionState();
    try {
      await ref.read(ocrWorkerProvider).cancelActive();
    } catch (_) {
      // Cancellation is a normal user action; the session is already idle.
    }
  }

  void reset() {
    _operation++;
    state = const CaptureSessionState();
  }
}

({CaptureFailure failure, String message}) _captureFailure(Object error) {
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
        message: 'This image could not be read. Choose a supported image file.',
      ),
      'ocr_failed' => (
        failure: CaptureFailure.ocr,
        message: 'Text recognition failed. Try another image.',
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
