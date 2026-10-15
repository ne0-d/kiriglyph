import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:kiriglyph/export/subject_cutout.dart';

class CanonicalSubjectMask {
  const CanonicalSubjectMask({
    required this.image,
    required this.decodeDuration,
  });

  final ui.Image image;
  final Duration decodeDuration;

  void dispose() => image.dispose();
}

Future<CanonicalSubjectMask> loadCanonicalSubjectMask(String path) async {
  final stopwatch = Stopwatch()..start();
  final encoded = await File(path).readAsBytes();
  final source = await _decodeRgba(encoded);
  try {
    final coverage = canonicalSubjectMaskRgba(source.rgba);
    final image = await _imageFromRgba(
      coverage,
      width: source.width,
      height: source.height,
    );
    stopwatch.stop();
    return CanonicalSubjectMask(
      image: image,
      decodeDuration: stopwatch.elapsed,
    );
  } finally {
    source.image.dispose();
  }
}

Uint8List canonicalSubjectMaskRgba(Uint8List rgba) {
  final coverage = Uint8List(rgba.length);
  for (var index = 0; index < rgba.length; index += 4) {
    final alpha = subjectMaskCoverage(rgba, index);
    coverage[index] = 255;
    coverage[index + 1] = 255;
    coverage[index + 2] = 255;
    coverage[index + 3] = alpha;
  }
  return coverage;
}

Future<_DecodedRgbaImage> _decodeRgba(Uint8List encoded) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
  final ui.ImageDescriptor descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
  } finally {
    buffer.dispose();
  }
  try {
    final codec = await descriptor.instantiateCodec();
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        image.dispose();
        throw StateError('mask could not be decoded');
      }
      return _DecodedRgbaImage(
        image: image,
        width: image.width,
        height: image.height,
        rgba: Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      );
    } finally {
      codec.dispose();
    }
  } finally {
    descriptor.dispose();
  }
}

Future<ui.Image> _imageFromRgba(
  Uint8List rgba, {
  required int width,
  required int height,
}) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

class _DecodedRgbaImage {
  const _DecodedRgbaImage({
    required this.image,
    required this.width,
    required this.height,
    required this.rgba,
  });

  final ui.Image image;
  final int width;
  final int height;
  final Uint8List rgba;
}
