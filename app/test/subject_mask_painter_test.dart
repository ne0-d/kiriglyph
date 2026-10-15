import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/segmentation/subject_segmenter.dart';
import 'package:kiriglyph/ui/overlay/subject_mask_alpha.dart';
import 'package:kiriglyph/ui/overlay/subject_overlay_layer.dart';
import 'package:kiriglyph/ui/workspace/fitted_image_geometry.dart';

void main() {
  testWidgets('legacy opaque grayscale mask draws a border, not a fill', (
    tester,
  ) async {
    final mask = (await tester.runAsync(
      () => _canonicalMask(_legacyGrayMask()),
    ))!;
    addTearDown(mask.dispose);

    final pixels = (await tester.runAsync(() => _paint(mask)))!;

    // The subject interior keeps its own pixels; only the surrounding ring
    // is drawn.
    expect(_pixel(pixels, 4, 1, 1), _basePixel);
    expect(_pixel(pixels, 4, 2, 2), _basePixel);
    expect(_pixel(pixels, 4, 0, 1), isNot(_basePixel));
  });

  testWidgets('true alpha mask matches legacy grayscale coverage', (
    tester,
  ) async {
    final legacy = (await tester.runAsync(
      () => _canonicalMask(_legacyGrayMask()),
    ))!;
    final alpha = (await tester.runAsync(
      () => _canonicalMask(_trueAlphaMask()),
    ))!;
    addTearDown(legacy.dispose);
    addTearDown(alpha.dispose);

    final legacyPixels = (await tester.runAsync(() => _paint(legacy)))!;
    final alphaPixels = (await tester.runAsync(() => _paint(alpha)))!;

    expect(_pixel(alphaPixels, 4, 1, 1), _basePixel);
    expect(_pixel(alphaPixels, 4, 0, 1), _pixel(legacyPixels, 4, 0, 1));
  });

  testWidgets('full black opaque mask paints nothing', (tester) async {
    final mask = (await tester.runAsync(
      () => _canonicalMask(_blackOpaqueMask()),
    ))!;
    addTearDown(mask.dispose);

    final pixels = (await tester.runAsync(() => _paint(mask)))!;

    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        expect(_pixel(pixels, 4, x, y), _basePixel);
      }
    }
  });
}

const _basePixel = [10, 20, 30, 255];

Future<ui.Image> _canonicalMask(Uint8List rgba) =>
    _imageFromRgba(canonicalSubjectMaskRgba(rgba), 4, 4);

Future<Uint8List> _paint(ui.Image mask) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(4, 4);
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = const Color.fromARGB(255, 10, 20, 30),
  );
  SubjectMaskPainter(
    mask: mask,
    geometry: FittedImageGeometry.contain(
      bounds: Offset.zero & size,
      imageSize: size,
    ),
    result: _result(),
    color: Colors.deepPurple,
    scrimOpacity: 0,
  ).paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 4);
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return Uint8List.fromList(
    bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
}

Uint8List _legacyGrayMask() {
  final rgba = Uint8List(4 * 4 * 4);
  for (var index = 0; index < rgba.length; index += 4) {
    rgba[index + 3] = 255;
  }
  for (final (x, y) in [(1, 1), (2, 1), (1, 2), (2, 2)]) {
    final offset = (y * 4 + x) * 4;
    rgba[offset] = 255;
    rgba[offset + 1] = 255;
    rgba[offset + 2] = 255;
  }
  return rgba;
}

Uint8List _trueAlphaMask() {
  final rgba = Uint8List(4 * 4 * 4);
  for (var index = 0; index < rgba.length; index += 4) {
    rgba[index] = 255;
    rgba[index + 1] = 255;
    rgba[index + 2] = 255;
  }
  for (final (x, y) in [(1, 1), (2, 1), (1, 2), (2, 2)]) {
    rgba[(y * 4 + x) * 4 + 3] = 255;
  }
  return rgba;
}

Uint8List _blackOpaqueMask() {
  final rgba = Uint8List(4 * 4 * 4);
  for (var index = 0; index < rgba.length; index += 4) {
    rgba[index + 3] = 255;
  }
  return rgba;
}

List<int> _pixel(Uint8List rgba, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return [rgba[offset], rgba[offset + 1], rgba[offset + 2], rgba[offset + 3]];
}

Future<ui.Image> _imageFromRgba(Uint8List rgba, int width, int height) {
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

SubjectMaskResult _result() {
  const bounds = SubjectRect(x: 1, y: 1, width: 2, height: 2);
  return const SubjectMaskResult(
    imageWidth: 4,
    imageHeight: 4,
    mask: SubjectMaskReference(path: '', byteLength: 0, sha256: ''),
    bounds: bounds,
    stats: SubjectMaskStats(
      outcome: SubjectMaskOutcome.ok,
      areaFraction: 0.25,
      bounds: bounds,
      touchesEdge: SubjectEdgeTouches(
        left: false,
        top: false,
        right: false,
        bottom: false,
      ),
      components: SubjectComponentStats(count: 1, largestBounds: bounds),
    ),
    timings: SubjectSegmentationTimings(promptMs: 1),
  );
}
