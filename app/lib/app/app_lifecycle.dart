import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/app/app_shell.dart';
import 'package:kiriglyph/capture/capture_session.dart';
import 'package:kiriglyph/diagnostics/timing_log.dart';
import 'package:kiriglyph/overlay/selection_overlay.dart';
import 'package:kiriglyph/providers.dart';

/// Connects native app commands to the selection overlay and the capture
/// session for the life of the process.
class AppLifecycle {
  AppLifecycle(this._container);

  final ProviderContainer _container;

  /// Starts the OCR worker so the first selection is fast, then accepts
  /// commands. The worker starts before any command can recognize an image.
  Future<void> start() async {
    unawaited(_warmWorker());
    await _container.read(appShellProvider).start(handle);
  }

  Future<void> handle(AppCommand command) async {
    final overlay = _container.read(selectionOverlayProvider.notifier);
    final session = _container.read(captureSessionProvider.notifier);
    switch (command) {
      case AppCommand.select:
        // This is the earliest Dart-visible point for a forwarded --select.
        if (!_container.read(selectionOverlayProvider).isActive) {
          _container.read(timingLogProvider).beginActivation();
        }
        await overlay.start();
      case AppCommand.overlayFocusLost:
        await overlay.handleFocusLost();
      case AppCommand.hidden || AppCommand.quit:
        // Closing the window ends every session and discards its capture.
        await overlay.dismiss();
        await session.discardSession();
    }
  }

  Future<void> _warmWorker() async {
    try {
      await _container.read(ocrWorkerProvider).restart();
    } catch (_) {
      // The first recognition retries startup and reports its failure.
    }
  }
}
