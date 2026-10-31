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

/// The overlay's display could not be found, or the overlay not shown on it.
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

  /// Opens the window from inside the app, as a second launch does: native
  /// has Dart paint the main screen first ([AppCommand.presented]) and then
  /// maps it. Use this rather than [present], which maps whatever the hidden
  /// window last painted, a transparent frame over black.
  Future<void> requestPresent();

  /// Hides the window if it is visible, so a capture cannot contain it.
  /// Completes once it is off screen, with whether it was visible.
  Future<bool> prepareCapture();

  /// Finds the display under the pointer with a small transparent probe
  /// window; the overlay itself is not shown. Completes with every display
  /// and the one under the pointer; throws [OverlayPlacementException].
  Future<DisplayPlacement> locateDisplay();

  /// Shows the window as a borderless fullscreen overlay on [display], the
  /// index of a monitor from [locateDisplay]. GNOME paints black behind a
  /// fullscreen window until one opaque buffer covers the display, so the
  /// window maps once, after Flutter has rendered what it should show.
  /// Completes once it is on screen; throws [OverlayPlacementException].
  Future<void> showOverlay(int display);

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
  Future<void> requestPresent() async {
    try {
      await _channel.invokeMethod<void>('requestPresent');
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
  Future<DisplayPlacement> locateDisplay() async {
    final reply = await _invokeOverlay('locateDisplay');
    try {
      return DisplayPlacement.fromChannel(reply);
    } on FormatException {
      throw const OverlayPlacementException('malformed');
    }
  }

  @override
  Future<void> showOverlay(int display) async {
    // The window's first buffer is the last frame Flutter rendered. The first
    // frame builds the overlay; the second gives it time to be rasterized.
    for (var frame = 0; frame < 2; frame++) {
      await _renderedFrame();
    }
    await _invokeOverlay('showOverlay', {'display': display});
  }

  Future<Object?> _invokeOverlay(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (error) {
      throw OverlayPlacementException(error.code);
    } on MissingPluginException {
      throw const OverlayPlacementException('unavailable');
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
