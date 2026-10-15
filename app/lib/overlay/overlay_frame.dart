import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/overlay/display_layout.dart';

/// The frozen pixels of one display, owned by the overlay session.
class OverlayFrame {
  OverlayFrame(this.image);

  final ui.Image image;

  int get width => image.width;
  int get height => image.height;

  void dispose() => image.dispose();
}

/// A decoded spanning capture, kept only until its display is cropped out.
abstract interface class DecodedCapture {
  int get width;
  int get height;

  Future<OverlayFrame> crop(OverlayCrop crop);

  void dispose();
}

/// Decodes, crops and re-encodes captures in memory. Only the crop is ever
/// encoded, for OCR; the spanning capture never touches disk again.
abstract interface class OverlayFrameCodec {
  Future<DecodedCapture> decode(Uint8List encoded);

  Future<Uint8List> encodePng(OverlayFrame frame);
}

/// [OverlayFrameCodec] on the engine's image codecs and rasterizer.
class EngineFrameCodec implements OverlayFrameCodec {
  const EngineFrameCodec();

  @override
  Future<DecodedCapture> decode(Uint8List encoded) async {
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
        return _EngineCapture(frame.image);
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  }

  @override
  Future<Uint8List> encodePng(OverlayFrame frame) async {
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('frame could not be encoded');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

class _EngineCapture implements DecodedCapture {
  _EngineCapture(this._image);

  final ui.Image _image;

  @override
  int get width => _image.width;

  @override
  int get height => _image.height;

  @override
  Future<OverlayFrame> crop(OverlayCrop crop) async {
    final source = crop.source;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      _image,
      ui.Rect.fromLTWH(
        source.left.toDouble(),
        source.top.toDouble(),
        source.width.toDouble(),
        source.height.toDouble(),
      ),
      ui.Rect.fromLTWH(
        0,
        0,
        crop.outputWidth.toDouble(),
        crop.outputHeight.toDouble(),
      ),
      ui.Paint()
        ..filterQuality = crop.resamples
            ? ui.FilterQuality.medium
            : ui.FilterQuality.none,
    );
    final picture = recorder.endRecording();
    try {
      return OverlayFrame(
        await picture.toImage(crop.outputWidth, crop.outputHeight),
      );
    } finally {
      picture.dispose();
    }
  }

  @override
  void dispose() => _image.dispose();
}

final overlayFrameCodecProvider = Provider<OverlayFrameCodec>(
  (ref) => const EngineFrameCodec(),
);
