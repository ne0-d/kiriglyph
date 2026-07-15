import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/protocol/protocol_error.dart';
import 'package:ubuntu_live_text/providers.dart';

enum CapturePhase { idle, recognizing, ready, error }

class CaptureSessionState {
  const CaptureSessionState({
    this.phase = CapturePhase.idle,
    this.imagePath,
    this.ocrResult,
    this.userMessage,
  });

  final CapturePhase phase;
  final String? imagePath;
  final OcrResult? ocrResult;
  final String? userMessage;

  CaptureSessionState copyWith({
    CapturePhase? phase,
    String? imagePath,
    OcrResult? ocrResult,
    String? userMessage,
    bool clearImagePath = false,
    bool clearOcrResult = false,
    bool clearUserMessage = false,
  }) {
    return CaptureSessionState(
      phase: phase ?? this.phase,
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
      ocrResult: clearOcrResult ? null : (ocrResult ?? this.ocrResult),
      userMessage: clearUserMessage ? null : (userMessage ?? this.userMessage),
    );
  }
}

class CaptureSessionController extends Notifier<CaptureSessionState> {
  @override
  CaptureSessionState build() => const CaptureSessionState();

  Future<void> openImage() async {
    final picker = ref.read(imagePickerProvider);
    final path = await picker.pickImagePath();
    if (path == null) {
      return;
    }

    state = state.copyWith(
      phase: CapturePhase.recognizing,
      imagePath: path,
      clearOcrResult: true,
      clearUserMessage: true,
    );

    try {
      final worker = ref.read(ocrWorkerProvider);
      final result = await worker.recognize(path);
      state = state.copyWith(
        phase: CapturePhase.ready,
        ocrResult: result,
        clearUserMessage: true,
      );
    } on WorkerError catch (error) {
      state = state.copyWith(
        phase: CapturePhase.error,
        userMessage: error.message,
        clearOcrResult: true,
      );
    } on ProtocolError {
      state = state.copyWith(
        phase: CapturePhase.error,
        userMessage: 'OCR worker protocol error. Try again.',
        clearOcrResult: true,
      );
    } catch (_) {
      state = state.copyWith(
        phase: CapturePhase.error,
        userMessage: 'Local OCR failed. Try again.',
        clearOcrResult: true,
      );
    }
  }

  void reset() {
    state = const CaptureSessionState();
  }
}

final captureSessionProvider =
    NotifierProvider<CaptureSessionController, CaptureSessionState>(
      CaptureSessionController.new,
    );
