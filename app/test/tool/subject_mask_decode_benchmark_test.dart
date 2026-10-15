import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/ui/overlay/subject_mask_alpha.dart';

void main() {
  testWidgets('measures canonical mask conversion cost', (tester) async {
    const width = 2560;
    const height = 1440;
    final rgba = Uint8List(width * height * 4);
    for (var index = 0; index < rgba.length; index += 4) {
      rgba[index + 3] = 255;
    }
    for (var y = 520; y < 920; y++) {
      for (var x = 960; x < 1600; x++) {
        final index = (y * width + x) * 4;
        rgba[index] = 255;
        rgba[index + 1] = 255;
        rgba[index + 2] = 255;
      }
    }

    final stopwatch = Stopwatch()..start();
    final canonical = canonicalSubjectMaskRgba(rgba);
    final image = (await tester.runAsync(
      () => _imageFromRgba(canonical, width: width, height: height),
    ))!;
    stopwatch.stop();
    addTearDown(image.dispose);

    // ignore: avoid_print
    print(
      'canonical alpha mask conversion 2560x1440: ${stopwatch.elapsedMilliseconds} ms',
    );
    expect(canonical[(720 * width + 1280) * 4 + 3], 255);
    expect(canonical[3], 0);
  });
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
