import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/overlay/display_layout.dart';

/// Commands the native runner delivers to Dart.
enum AppCommand {
  /// The selection command ran (`--select`), locally or forwarded from a
  /// second launch.
  select,

  /// The user closed the window of a resident instance; it is now hidden.
  hidden,

  /// `--quit` ran; the process exits once the handler completes.
  quit,

  /// The overlay window lost focus to another window or display.
  overlayFocusLost,

  /// The window was presented as the normal app window.
  presented,
}

typedef AppCommandHandler = Future<void> Function(AppCommand command);

/// The overlay window could not be placed on a display.
class OverlayPlacementException implements Exception {
  const OverlayPlacementException(this.code);

  final String code;

  @override
  String toString() => 'OverlayPlacementException($code)';
}

/// The native application shell: a single resident GApplication instance
/// whose window can be hidden while the engine keeps running.
abstract interface class AppShell {
  /// Registers [handler] and releases commands queued before Dart started.
  Future<void> start(AppCommandHandler handler);

  /// Shows and raises the window, once Flutter has rendered the screen it
  /// should show. A window maps with the last frame Flutter rendered, which
  /// for a hidden window is a stale one over an opaque black background.
  Future<void> present();

  /// Hides the window if it is visible, so a capture cannot contain it.
  /// Completes once it is off screen, with whether it was visible.
  Future<bool> prepareCapture();

  /// Shows the window as a borderless fullscreen overlay on the display under
  /// the pointer. Flutter's view stays hidden and the window is a transparent
  /// GTK surface until [revealOverlay]. Completes with the display it landed
  /// on; throws [OverlayPlacementException].
  Future<DisplayPlacement> showOverlay();

  /// Shows Flutter's view in the already-mapped overlay, after Flutter has
  /// painted the frozen frame and native GTK has presented paint cycles.
  Future<void> revealOverlay();

  /// Hides the overlay and restores the normal window for next time.
  Future<void> hideOverlay();

  /// Suppresses focus-loss dismissal while a trusted native dialog is open.
  Future<void> setOverlayFocusLossSuppressed(bool suppressed);

  /// Exits the resident application process.
  Future<void> requestQuit();
}

/// [AppShell] over the `kiriglyph/app` channel in `linux/runner`.
class PlatformAppShell implements AppShell {
  PlatformAppShell({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('kiriglyph/app');

  final MethodChannel _channel;

  static const _frameWait = Duration(milliseconds: 500);

  /// Completes after the next frame, or after [_frameWait] if none comes.
  Future<void> _renderedFrame() => SchedulerBinding.instance.endOfFrame.timeout(
    _frameWait,
    onTimeout: () {},
  );

  @override
  Future<void> start(AppCommandHandler handler) async {
    _channel.setMethodCallHandler((call) async {
      final command = switch (call.method) {
        'select' => AppCommand.select,
        'hidden' => AppCommand.hidden,
        'quit' => AppCommand.quit,
        'overlayFocusLost' => AppCommand.overlayFocusLost,
        'presented' => AppCommand.presented,
        _ => null,
      };
      if (command == null) {
        throw MissingPluginException(call.method);
      }
      await handler(command);
    });
    try {
      await _channel.invokeMethod<void>('ready');
    } on MissingPluginException {
      // Not running under the Kiriglyph runner, e.g. in widget tests.
    }
  }

  @override
  Future<void> present() async {
    // Flutter renders while the window is hidden. The first frame builds the
    // screen; the second gives it time to be rasterized before the window maps.
    for (var frame = 0; frame < 2; frame++) {
      await _renderedFrame();
    }
    try {
      await _channel.invokeMethod<void>('present');
    } on MissingPluginException {
      // Not running under the Kiriglyph runner.
    }
  }

  @override
  Future<bool> prepareCapture() async {
    try {
      return await _channel.invokeMethod<bool>('prepareCapture') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<DisplayPlacement> showOverlay() async {
    // The window maps with whatever Flutter last rendered, so let the
    // transparent overlay frame render first.
    await _renderedFrame();
    final Object? reply;
    try {
      reply = await _channel.invokeMethod<Object?>('showOverlay');
    } on PlatformException catch (error) {
      throw OverlayPlacementException(error.code);
    } on MissingPluginException {
      throw const OverlayPlacementException('unavailable');
    }
    try {
      return DisplayPlacement.fromChannel(reply);
    } on FormatException {
      throw const OverlayPlacementException('malformed');
    }
  }

  @override
  Future<void> revealOverlay() async {
    await _renderedFrame();
    try {
      await _channel.invokeMethod<void>('revealOverlay');
    } on MissingPluginException {
      // Not running under the Kiriglyph runner.
    }
  }

  @override
  Future<void> hideOverlay() async {
    try {
      await _channel.invokeMethod<void>('hideOverlay');
    } on MissingPluginException {
      // Not running under the Kiriglyph runner.
    }
  }

  @override
  Future<void> setOverlayFocusLossSuppressed(bool suppressed) async {
    try {
      await _channel.invokeMethod<void>('setOverlayFocusLossSuppressed', {
        'suppressed': suppressed,
      });
    } on MissingPluginException {
      // Not running under the Kiriglyph runner.
    }
  }

  @override
  Future<void> requestQuit() async {
    try {
      await _channel.invokeMethod<void>('requestQuit');
    } on MissingPluginException {
      // Not running under the Kiriglyph runner, e.g. in widget tests.
    }
  }
}

final appShellProvider = Provider<AppShell>((ref) => PlatformAppShell());
