import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kiriglyph/capture/screen_capture.dart';
import 'package:kiriglyph/worker/process_ocr_worker.dart';

/// Runs the one-shot Python portal helper for each capture.
class PortalHelperScreenCapture implements ScreenCapturePort {
  PortalHelperScreenCapture(this._launchConfig);

  final WorkerLaunchConfig _launchConfig;
  Process? _process;

  @override
  Future<ScreenCapture> capture() async {
    await cancel();
    final Process process;
    try {
      process = await Process.start(
        _launchConfig.executable,
        _launchConfig.arguments,
        workingDirectory: _launchConfig.workingDirectory,
        environment: _launchConfig.environment,
      );
    } on ProcessException {
      return const ScreenCapture(ScreenCaptureStatus.unavailable);
    }
    _process = process;
    final stderrDone = process.stderr.drain<void>();
    final stdout = await process.stdout.transform(const Utf8Decoder()).join();
    await process.exitCode;
    await stderrDone;
    if (!identical(_process, process)) {
      return const ScreenCapture(ScreenCaptureStatus.cancelled);
    }
    _process = null;
    return parseScreenCaptureOutput(stdout);
  }

  @override
  Future<void> cancel() async {
    final process = _process;
    _process = null;
    process?.kill();
  }
}
