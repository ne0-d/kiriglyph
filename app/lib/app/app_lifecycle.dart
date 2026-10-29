import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/app/app_shell.dart';
import 'package:kiriglyph/app/window_surface.dart';
import 'package:kiriglyph/background/shortcut_pause.dart';
import 'package:kiriglyph/capture/capture_session.dart';
import 'package:kiriglyph/diagnostics/timing_log.dart';
import 'package:kiriglyph/overlay/selection_overlay.dart';
import 'package:kiriglyph/providers.dart';
import 'package:kiriglyph/tray/status_notifier.dart';

/// Connects native app commands to the selection overlay and the capture
/// session for the life of the process.
class AppLifecycle {
  AppLifecycle(this._container);

  final ProviderContainer _container;
  StatusNotifierService? _tray;

  /// Starts the OCR worker so the first selection is fast, then accepts
  /// commands. The worker starts before any command can recognize an image.
  Future<void> start() async {
    unawaited(_warmWorker());
    await _container.read(appShellProvider).start(handle);
    unawaited(_startTray());
  }

  Future<void> handle(AppCommand command) async {
    final overlay = _container.read(selectionOverlayProvider.notifier);
    final session = _container.read(captureSessionProvider.notifier);
    switch (command) {
      case AppCommand.select:
        if (_container.read(shortcutPauseProvider)) {
          return;
        }
        _container
            .read(trayStateProvider.notifier)
            .setVisual(TrayVisualState.busy, statusLabel: 'Ready');
        // This is the earliest Dart-visible point for a forwarded --select.
        if (!_container.read(selectionOverlayProvider).isActive) {
          _container.read(timingLogProvider).beginActivation();
          _container.read(timingLogProvider).mark(TimingPhase.forward);
        }
        await overlay.start();
        _container
            .read(trayStateProvider.notifier)
            .setVisual(TrayVisualState.idle, statusLabel: 'Ready');
      case AppCommand.overlayFocusLost:
        await overlay.handleFocusLost();
      case AppCommand.presented:
        _container.read(mainWindowShownProvider.notifier).shown();
        // Native maps the window when this returns, so the main screen is
        // already rendered and not the transparent frame the hidden window kept.
        await _container.read(appShellProvider).present();
      case AppCommand.hidden:
        _container.read(mainWindowShownProvider.notifier).hidden();
        // Closing the window ends every session and discards its capture.
        await overlay.dismiss();
        await session.discardSession();
      case AppCommand.quit:
        // Quit exits the resident process; stop local workers before native
        // tears down the engine.
        await overlay.dismiss();
        await session.discardSession();
        await _tray?.dispose();
        await _container.read(ocrWorkerProvider).close();
    }
  }

  Future<void> _warmWorker() async {
    try {
      await _container.read(ocrWorkerProvider).restart();
    } catch (_) {
      // The first recognition retries startup and reports its failure.
    }
  }

  Future<void> _startTray() async {
    try {
      _tray = await startStatusNotifier(
        container: _container,
        select: () => handle(AppCommand.select),
      );
    } catch (_) {
      // A missing or inaccessible session bus should not stop the resident app.
    }
  }
}
