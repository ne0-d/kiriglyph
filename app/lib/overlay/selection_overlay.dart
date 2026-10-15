import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/app/app_shell.dart';
import 'package:kiriglyph/capture/capture_session.dart';
import 'package:kiriglyph/capture/screen_capture.dart';
import 'package:kiriglyph/capture/session_image_store.dart';
import 'package:kiriglyph/diagnostics/timing_log.dart';
import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/overlay/display_layout.dart';
import 'package:kiriglyph/overlay/overlay_frame.dart';
import 'package:kiriglyph/providers.dart';
import 'package:kiriglyph/segmentation/subject_segmenter.dart';
import 'package:kiriglyph/selection/selection_intent.dart';

enum OverlayPhase {
  /// No overlay; the window is hidden or in its normal mode.
  idle,

  /// The window is hidden while the silent capture runs.
  capturing,

  /// The overlay window is mapped, transparent, and finding its display.
  placing,

  /// The frozen frame is shown while OCR runs.
  recognizing,

  /// Text on the frozen frame is selectable.
  ready,

  /// A brief message is shown before the overlay closes by itself.
  failed,
}

class SelectionOverlayState {
  const SelectionOverlayState({
    this.phase = OverlayPhase.idle,
    this.frame,
    this.ocrResult,
    this.message,
    this.subjectImagePath,
    this.subjectEmbedding,
    this.exportInProgress = false,
    this.activeSelection = SelectionActiveKind.none,
  });

  final OverlayPhase phase;

  /// The frozen display, from [OverlayPhase.recognizing] on. A failure before
  /// the frame was ready has none.
  final OverlayFrame? frame;

  /// Recognized text in [frame] pixels; set only when [phase] is ready.
  final OcrResult? ocrResult;

  /// User-safe failure text for [OverlayPhase.failed].
  final String? message;

  /// Private crop path for the active capture, used only by local workers.
  final String? subjectImagePath;

  /// The one subject embedding for this overlay session, started after OCR.
  final Future<SubjectEmbedding>? subjectEmbedding;

  /// A native export dialog owns focus while the overlay session is retained.
  final bool exportInProgress;

  final SelectionActiveKind activeSelection;

  bool get isActive => phase != OverlayPhase.idle;
}

/// How long overlay steps may take before the overlay gives up.
class OverlayTimeouts {
  const OverlayTimeouts({
    this.content = const Duration(seconds: 5),
    this.failureMessage = const Duration(milliseconds: 3500),
  });

  /// From the end of the capture until the frozen frame is shown.
  final Duration content;

  /// How long a failure stays on screen before the overlay closes.
  final Duration failureMessage;
}

final overlayTimeoutsProvider = Provider<OverlayTimeouts>(
  (ref) => const OverlayTimeouts(),
);

const permissionNotice =
    'Instant capture is not enabled yet. Choose “Enable instant capture”, '
    'then use the shortcut again.';
const overlayStartNotice =
    'Selection mode could not start. Try the shortcut again.';

const noTextSubjectNotice = 'No text found - click or draw around an object';
const _noTextMessage = 'No text was found on this display.';
const _layoutMessage = 'This display layout is not supported yet.';
const _captureMessages = {
  ScreenCaptureStatus.unavailable:
      'Screen capture is unavailable. It needs GNOME on Wayland with the '
      'screenshot portal installed.',
  ScreenCaptureStatus.invalidUri: 'The screenshot could not be located.',
  ScreenCaptureStatus.unreadable: 'The screenshot could not be read.',
};
const _captureFailedMessage = 'Screen capture failed. Try again.';

/// One shortcut selection: a silent capture of every display, the display
/// under the pointer frozen in a fullscreen overlay, and OCR of that display
/// only. Dismissing discards the frame, the private image copy and the text.
class SelectionOverlayController extends Notifier<SelectionOverlayState> {
  int _operation = 0;
  SessionImage? _image;
  bool _windowShown = false;
  Timer? _contentTimer;
  Timer? _failureTimer;

  @override
  SelectionOverlayState build() {
    ref.onDispose(() {
      _contentTimer?.cancel();
      _failureTimer?.cancel();
      _image?.discard();
    });
    return const SelectionOverlayState();
  }

  AppShell get _shell => ref.read(appShellProvider);

  /// Starts a selection. Returns false and does nothing while an overlay is
  /// already capturing or shown, so repeated shortcuts never stack.
  Future<bool> start() async {
    if (state.isActive) {
      return false;
    }
    final operation = ++_operation;
    state = const SelectionOverlayState(phase: OverlayPhase.capturing);
    ref.read(selectionNoticeProvider.notifier).clear();

    await ref.read(captureSessionProvider.notifier).discardSession();
    try {
      await _shell.prepareCapture();
    } catch (_) {
      // Capturing anyway is better than not responding to the shortcut.
    }
    if (operation != _operation) {
      return true;
    }

    var capture = const ScreenCapture(ScreenCaptureStatus.failed);
    try {
      capture = await ref.read(silentScreenCaptureProvider).capture();
    } catch (_) {
      // Reported as a failed capture below.
    }
    ref.read(timingLogProvider).mark(TimingPhase.capture);
    final store = ref.read(sessionImageStoreProvider);
    final returnedPath = capture.path;
    if (operation != _operation) {
      if (returnedPath != null) {
        await store.deleteReturned(returnedPath);
      }
      return true;
    }

    if (capture.status == ScreenCaptureStatus.ended ||
        capture.status == ScreenCaptureStatus.cancelled ||
        capture.status == ScreenCaptureStatus.denied) {
      ref.read(timingLogProvider).finish(TimingOutcome.permissionRequired);
      await _openOnboarding(permissionNotice);
      return true;
    }
    if (capture.status != ScreenCaptureStatus.captured ||
        returnedPath == null) {
      ref.read(timingLogProvider).finish(TimingOutcome.failed);
      await _failWithoutFrame(
        operation,
        _captureMessages[capture.status] ?? _captureFailedMessage,
      );
      return true;
    }

    final Uint8List encoded;
    try {
      encoded = await store.take(returnedPath);
    } on FileSystemException {
      if (operation == _operation) {
        ref.read(timingLogProvider).finish(TimingOutcome.failed);
        await _failWithoutFrame(
          operation,
          _captureMessages[ScreenCaptureStatus.unreadable]!,
        );
      }
      return true;
    }
    if (operation != _operation) {
      return true;
    }
    await _freeze(operation, encoded);
    return true;
  }

  /// Leaves the overlay and discards everything the selection produced.
  Future<void> dismiss() async {
    if (!state.isActive) {
      return;
    }
    final recognizing = state.phase == OverlayPhase.recognizing;
    _operation++;
    _contentTimer?.cancel();
    _failureTimer?.cancel();
    final frame = state.frame;
    state = const SelectionOverlayState();
    frame?.dispose();
    if (_windowShown) {
      _windowShown = false;
      try {
        await _shell.hideOverlay();
      } catch (_) {
        // The window is gone with the engine; nothing is left on screen.
      }
    }
    await _releaseImage();
    await _closeSubjectSegmenter();
    ref.read(timingLogProvider).finish(TimingOutcome.dismissed);
    if (recognizing) {
      // Stops OCR of the discarded frame and warms a fresh worker.
      unawaited(_restartWorker());
    }
  }

  Future<void> handleFocusLost() async {
    if (state.exportInProgress) {
      return;
    }
    await dismiss();
  }

  /// Keeps the overlay session alive while a trusted native dialog is open.
  Future<void> beginExportInteraction() async {
    if (!state.isActive || state.exportInProgress) {
      return;
    }
    final current = state;
    state = SelectionOverlayState(
      phase: current.phase,
      frame: current.frame,
      ocrResult: current.ocrResult,
      message: current.message,
      subjectImagePath: current.subjectImagePath,
      subjectEmbedding: current.subjectEmbedding,
      exportInProgress: true,
      activeSelection: current.activeSelection,
    );
    await _shell.setOverlayFocusLossSuppressed(true);
  }

  Future<void> completeExportInteraction({required bool dismissOverlay}) async {
    if (!state.exportInProgress) {
      return;
    }
    await _shell.setOverlayFocusLossSuppressed(false);
    if (dismissOverlay) {
      await dismiss();
      return;
    }
    final current = state;
    state = SelectionOverlayState(
      phase: current.phase,
      frame: current.frame,
      ocrResult: current.ocrResult,
      message: current.message,
      subjectImagePath: current.subjectImagePath,
      subjectEmbedding: current.subjectEmbedding,
      activeSelection: current.activeSelection,
    );
  }

  Future<void> _freeze(int operation, Uint8List encoded) async {
    final codec = ref.read(overlayFrameCodecProvider);
    final decoding = codec
        .decode(encoded)
        .then<DecodedCapture?>((capture) => capture, onError: (_) => null);

    final placement = await _place(operation);
    if (placement == null) {
      unawaited(decoding.then((capture) => capture?.dispose()));
      return;
    }
    final decoded = await decoding;
    if (operation != _operation) {
      decoded?.dispose();
      return;
    }
    if (decoded == null) {
      _fail(operation, _captureMessages[ScreenCaptureStatus.unreadable]!);
      return;
    }

    final OverlayFrame frame;
    try {
      final crop = computeOverlayCrop(
        placement: placement,
        imageWidth: decoded.width,
        imageHeight: decoded.height,
      );
      frame = await decoded.crop(crop);
      ref.read(timingLogProvider).mark(TimingPhase.crop);
    } on DisplayLayoutMismatch {
      decoded.dispose();
      _fail(operation, _layoutMessage);
      return;
    } catch (_) {
      decoded.dispose();
      _fail(operation, _captureMessages[ScreenCaptureStatus.unreadable]!);
      return;
    }
    // The spanning capture of every display is no longer needed.
    decoded.dispose();
    if (operation != _operation) {
      frame.dispose();
      return;
    }
    _contentTimer?.cancel();
    state = SelectionOverlayState(
      phase: OverlayPhase.recognizing,
      frame: frame,
    );
    await _recognize(operation, codec, frame);
  }

  Future<void> _recognize(
    int operation,
    OverlayFrameCodec codec,
    OverlayFrame frame,
  ) async {
    final OcrResult result;
    try {
      final image = await ref
          .read(sessionImageStoreProvider)
          .write(await codec.encodePng(frame));
      if (operation != _operation) {
        await image.discard();
        return;
      }
      _image = image;
      result = await ref.read(ocrWorkerProvider).recognize(image.path);
      ref.read(timingLogProvider).mark(TimingPhase.ocr);
    } catch (error) {
      if (operation == _operation) {
        final failure = recognitionFailureOf(error);
        _fail(
          operation,
          failure.failure == CaptureFailure.noText
              ? _noTextMessage
              : failure.message,
        );
      }
      return;
    }
    if (operation != _operation) {
      return;
    }
    if (result.regions.isEmpty) {
      state = SelectionOverlayState(
        phase: OverlayPhase.ready,
        frame: frame,
        ocrResult: result,
        subjectImagePath: _image?.path,
        subjectEmbedding: _image == null ? null : _startEmbedding(_image!.path),
        activeSelection: SelectionActiveKind.none,
      );
      return;
    }
    state = SelectionOverlayState(
      phase: OverlayPhase.ready,
      frame: frame,
      ocrResult: result,
      subjectImagePath: _image?.path,
      subjectEmbedding: _image == null ? null : _startEmbedding(_image!.path),
      activeSelection: SelectionActiveKind.none,
    );
  }

  void setActiveSelection(SelectionActiveKind activeSelection) {
    final current = state;
    if (!current.isActive || current.activeSelection == activeSelection) {
      return;
    }
    state = SelectionOverlayState(
      phase: current.phase,
      frame: current.frame,
      ocrResult: current.ocrResult,
      message: current.message,
      subjectImagePath: current.subjectImagePath,
      subjectEmbedding: current.subjectEmbedding,
      exportInProgress: current.exportInProgress,
      activeSelection: activeSelection,
    );
  }

  /// Starts the session's single embedding. The state holds the future before
  /// any widget listens, so closing the segmenter early (dismissal during the
  /// embed) must not surface as an unhandled async error; listeners that await
  /// it later still receive the failure.
  Future<SubjectEmbedding> _startEmbedding(String imagePath) {
    final embedding = ref.read(subjectSegmenterProvider).embed(imagePath);
    embedding.ignore();
    return embedding;
  }

  /// Shows the transparent overlay window and waits for its display. Gives up
  /// after [OverlayTimeouts.content] if no frame could be shown by then.
  Future<DisplayPlacement?> _place(int operation) async {
    state = const SelectionOverlayState(phase: OverlayPhase.placing);
    _windowShown = true;
    _contentTimer?.cancel();
    _contentTimer = Timer(ref.read(overlayTimeoutsProvider).content, () {
      if (operation == _operation && state.phase == OverlayPhase.placing) {
        unawaited(_abandon());
      }
    });
    try {
      final placement = await _shell.showOverlay();
      ref
          .read(timingLogProvider)
          .setDisplay(
            count: placement.monitors.length,
            scale: placement.monitors[placement.targetIndex].scaleFactor
                .toDouble(),
          );
      return placement;
    } catch (_) {
      if (operation == _operation) {
        await _abandon();
      }
      return null;
    }
  }

  /// A failure the user can read on screen; the overlay closes by itself.
  Future<void> _failWithoutFrame(int operation, String message) async {
    if (await _place(operation) == null || operation != _operation) {
      return;
    }
    _fail(operation, message);
  }

  void _fail(int operation, String message) {
    _contentTimer?.cancel();
    ref.read(timingLogProvider).finish(TimingOutcome.failed);
    state = SelectionOverlayState(
      phase: OverlayPhase.failed,
      frame: state.frame,
      message: message,
    );
    _failureTimer?.cancel();
    _failureTimer = Timer(ref.read(overlayTimeoutsProvider).failureMessage, () {
      if (operation == _operation) {
        unawaited(dismiss());
      }
    });
  }

  /// The overlay could not be shown: close it and explain in the normal
  /// window instead of leaving the display covered.
  Future<void> _abandon() async {
    await dismiss();
    ref.read(selectionNoticeProvider.notifier).show(overlayStartNotice);
    await _present();
  }

  Future<void> _openOnboarding(String notice) async {
    _operation++;
    state = const SelectionOverlayState();
    ref.read(selectionNoticeProvider.notifier).show(notice);
    await _present();
  }

  Future<void> _present() async {
    try {
      await _shell.present();
    } catch (_) {
      // Without a window there is nowhere else to report the failure.
    }
  }

  Future<void> _releaseImage() async {
    final image = _image;
    _image = null;
    await image?.discard();
  }

  Future<void> _closeSubjectSegmenter() async {
    final segmenter = ref.read(subjectSegmenterProvider);
    try {
      await segmenter.close();
    } catch (_) {
      // Closing is cleanup; a dead worker is already gone.
    }
    ref.invalidate(subjectSegmenterProvider);
  }

  Future<void> _restartWorker() async {
    try {
      await ref.read(ocrWorkerProvider).restart();
    } catch (_) {
      // The next recognition retries startup and reports its failure.
    }
  }
}

final selectionOverlayProvider =
    NotifierProvider<SelectionOverlayController, SelectionOverlayState>(
      SelectionOverlayController.new,
    );

/// A message for the normal window about the last shortcut selection.
class SelectionNoticeController extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String message) => state = message;

  void clear() => state = null;
}

final selectionNoticeProvider =
    NotifierProvider<SelectionNoticeController, String?>(
      SelectionNoticeController.new,
    );
