import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:kiriglyph/app/app_shell.dart';
import 'package:kiriglyph/capture/screen_capture.dart';
import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/overlay/display_layout.dart';
import 'package:kiriglyph/overlay/overlay_frame.dart';
import 'package:kiriglyph/protocol/worker_protocol.dart';
import 'package:kiriglyph/worker/ocr_worker.dart';

/// Two displays side by side: a 200x100 one and a 100x50 one to its right.
const twoDisplays = DisplayPlacement(
  monitors: [
    LogicalMonitor(x: 0, y: 0, width: 200, height: 100),
    LogicalMonitor(x: 200, y: 0, width: 100, height: 50),
  ],
  targetIndex: 0,
);

/// Waits in real time until [condition] holds, for flows that do file IO.
Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class FakeShell implements AppShell {
  AppCommandHandler? handler;
  final events = <String>[];
  DisplayPlacement placement = twoDisplays;
  Object? placementError;

  /// When set, `locateDisplay` waits for it; `hideOverlay` cancels it.
  Completer<DisplayPlacement>? placementGate;

  /// The display index of the last `showOverlay`.
  int? shownDisplay;
  Object? showError;

  /// When set, `showOverlay` waits for it; `hideOverlay` cancels it.
  Completer<void>? showGate;

  int count(String event) => events.where((e) => e == event).length;

  @override
  Future<void> start(AppCommandHandler handler) async => this.handler = handler;

  @override
  Future<void> present() async => events.add('present');

  /// Like the native runner: ask Dart to paint the main screen, which then
  /// maps the window with `present`.
  @override
  Future<void> requestPresent() async {
    events.add('request-present');
    await handler?.call(AppCommand.presented);
  }

  @override
  Future<bool> prepareCapture() async {
    events.add('prepare');
    return false;
  }

  @override
  Future<DisplayPlacement> locateDisplay() async {
    events.add('locate');
    final gate = placementGate;
    if (gate != null) {
      return gate.future;
    }
    final error = placementError;
    if (error != null) {
      throw error;
    }
    return placement;
  }

  @override
  Future<void> showOverlay(int display) async {
    events.add('show');
    shownDisplay = display;
    await showGate?.future;
    final error = showError;
    if (error != null) {
      throw error;
    }
  }

  /// Like the native runner, hiding cancels a pending locate or show.
  @override
  Future<void> hideOverlay() async {
    events.add('hide');
    for (final gate in <Completer<Object?>?>[placementGate, showGate]) {
      if (gate != null && !gate.isCompleted) {
        gate.future.ignore();
        gate.completeError(const OverlayPlacementException('cancelled'));
      }
    }
  }

  @override
  Future<void> setOverlayFocusLossSuppressed(bool suppressed) async =>
      events.add(suppressed ? 'suppress-focus' : 'unsuppress-focus');

  @override
  Future<void> requestQuit() async => events.add('quit');
}

/// Writes a fresh file into a fake Pictures folder per capture, as GNOME does.
class FakeSilentPortal implements ScreenCapturePort {
  FakeSilentPortal(this.pictures);

  final Directory pictures;
  ScreenCaptureStatus status = ScreenCaptureStatus.captured;
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<ScreenCapture> capture() async {
    calls++;
    await gate?.future;
    if (status != ScreenCaptureStatus.captured) {
      return ScreenCapture(status);
    }
    final file = File('${pictures.path}/Screenshot-$calls.png')
      ..writeAsBytesSync([calls]);
    return ScreenCapture(status, path: file.path);
  }

  @override
  Future<void> cancel() async {}
}

/// Decodes any bytes to a capture of [width] x [height] and records crops.
/// Frames share one real [ui.Image] through clones.
class FakeFrameCodec implements OverlayFrameCodec {
  FakeFrameCodec(this.image, {this.width = 300, this.height = 100});

  final ui.Image image;
  int width;
  int height;
  bool failDecode = false;
  final decoded = <Uint8List>[];
  final crops = <OverlayCrop>[];
  final encodedFrames = <OverlayFrame>[];

  static final encodedBytes = Uint8List.fromList([0x89, 1, 2, 3]);

  @override
  Future<DecodedCapture> decode(Uint8List encoded) async {
    decoded.add(encoded);
    if (failDecode) {
      throw const FormatException('not an image');
    }
    return _FakeCapture(this);
  }

  @override
  Future<Uint8List> encodePng(OverlayFrame frame) async {
    encodedFrames.add(frame);
    return encodedBytes;
  }
}

class _FakeCapture implements DecodedCapture {
  _FakeCapture(this._codec);

  final FakeFrameCodec _codec;
  bool disposed = false;

  @override
  int get width => _codec.width;

  @override
  int get height => _codec.height;

  @override
  Future<OverlayFrame> crop(OverlayCrop crop) async {
    _codec.crops.add(crop);
    return OverlayFrame(_codec.image.clone());
  }

  @override
  void dispose() => disposed = true;
}

/// Answers each recognition from [next], or holds it until completed.
class ControlledWorker implements OcrWorker {
  ControlledWorker([this.next]);

  OcrResult? next;
  Object? error;
  List<DecodedCode> nextCodes = const [];
  final paths = <String>[];
  final codePaths = <String>[];
  final pending = <Completer<OcrResult>>[];
  final pendingCodes = <Completer<List<DecodedCode>>>[];
  int restarts = 0;
  int cancels = 0;
  int inFlightCancels = 0;

  @override
  Future<OcrResult> recognize(String imagePath) async {
    paths.add(imagePath);
    final error = this.error;
    if (error != null) {
      throw error;
    }
    final result = next;
    if (result != null) {
      return result;
    }
    final completer = Completer<OcrResult>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<List<DecodedCode>> decodeCodes(String imagePath) async {
    codePaths.add(imagePath);
    if (nextCodes.isNotEmpty) {
      return nextCodes;
    }
    final completer = Completer<List<DecodedCode>>();
    pendingCodes.add(completer);
    return completer.future;
  }

  @override
  Future<void> restart() async => restarts++;

  @override
  Future<void> cancelInFlight() async => inFlightCancels++;

  @override
  Future<void> cancelActive() async => cancels++;

  @override
  Future<void> close() async {}
}
