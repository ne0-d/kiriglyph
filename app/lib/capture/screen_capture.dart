import 'dart:convert';

enum ScreenCaptureStatus {
  captured,
  cancelled,
  ended,
  unavailable,
  denied,
  failed,
  invalidUri,
  unreadable,
}

class ScreenCapture {
  const ScreenCapture(this.status, {this.path});

  final ScreenCaptureStatus status;

  /// Readable image path; set only when [status] is
  /// [ScreenCaptureStatus.captured]. An interactive capture's file belongs to
  /// GNOME and is never deleted. A silent capture's file belongs to the app,
  /// which deletes exactly this path after reading it.
  final String? path;

  /// The user closed the system selector; not an error.
  bool get isNeutral =>
      status == ScreenCaptureStatus.cancelled ||
      status == ScreenCaptureStatus.ended;
}

abstract class ScreenCapturePort {
  Future<ScreenCapture> capture();

  /// Stops waiting for an in-flight capture. Its late result is discarded.
  Future<void> cancel();
}

/// Parses the single JSON line printed by the portal capture helper.
ScreenCapture parseScreenCaptureOutput(String stdout) {
  final lines = const LineSplitter()
      .convert(stdout)
      .where((line) => line.trim().isNotEmpty)
      .toList();
  if (lines.length != 1) {
    return const ScreenCapture(ScreenCaptureStatus.failed);
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(lines.single);
  } on FormatException {
    return const ScreenCapture(ScreenCaptureStatus.failed);
  }
  if (decoded is! Map<String, Object?>) {
    return const ScreenCapture(ScreenCaptureStatus.failed);
  }
  final status = switch (decoded['outcome']) {
    'captured' => ScreenCaptureStatus.captured,
    'cancelled' => ScreenCaptureStatus.cancelled,
    'ended' => ScreenCaptureStatus.ended,
    'unavailable' => ScreenCaptureStatus.unavailable,
    'denied' => ScreenCaptureStatus.denied,
    'invalid_uri' => ScreenCaptureStatus.invalidUri,
    'unreadable' => ScreenCaptureStatus.unreadable,
    _ => ScreenCaptureStatus.failed,
  };
  if (status != ScreenCaptureStatus.captured) {
    return ScreenCapture(status);
  }
  final path = decoded['path'];
  if (path is! String || !path.startsWith('/')) {
    return const ScreenCapture(ScreenCaptureStatus.invalidUri);
  }
  return ScreenCapture(status, path: path);
}
