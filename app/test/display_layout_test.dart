import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/overlay/display_layout.dart';
import 'package:kiriglyph/overlay/overlay_frame.dart';

OverlayCrop crop(
  List<LogicalMonitor> monitors,
  int target,
  int imageWidth,
  int imageHeight,
) => computeOverlayCrop(
  placement: DisplayPlacement(monitors: monitors, targetIndex: target),
  imageWidth: imageWidth,
  imageHeight: imageHeight,
);

void main() {
  group('computeOverlayCrop', () {
    test('a single display at 100% is the whole capture', () {
      final result = crop(
        const [LogicalMonitor(x: 0, y: 0, width: 2560, height: 1440)],
        0,
        2560,
        1440,
      );
      expect(result.source, const PixelRect(0, 0, 2560, 1440));
      expect((result.outputWidth, result.outputHeight), (2560, 1440));
      expect(result.imageScale, 1);
      expect(result.resamples, isFalse);
    });

    test('two displays side by side at 100%', () {
      const monitors = [
        LogicalMonitor(x: 0, y: 0, width: 2560, height: 1440),
        LogicalMonitor(x: 2560, y: 0, width: 1920, height: 1080),
      ];
      expect(
        crop(monitors, 0, 4480, 1440).source,
        const PixelRect(0, 0, 2560, 1440),
      );
      final second = crop(monitors, 1, 4480, 1440);
      expect(second.source, const PixelRect(2560, 0, 1920, 1080));
      expect((second.outputWidth, second.outputHeight), (1920, 1080));
    });

    test('a vertical offset and a display above the origin', () {
      const offset = [
        LogicalMonitor(x: 0, y: 360, width: 1920, height: 1080),
        LogicalMonitor(x: 1920, y: 0, width: 2560, height: 1440),
      ];
      expect(
        crop(offset, 0, 4480, 1440).source,
        const PixelRect(0, 360, 1920, 1080),
      );

      const stacked = [
        LogicalMonitor(x: 0, y: -1080, width: 1920, height: 1080),
        LogicalMonitor(x: 0, y: 0, width: 2560, height: 1440),
      ];
      expect(
        crop(stacked, 0, 2560, 2520).source,
        const PixelRect(0, 0, 1920, 1080),
      );
      expect(
        crop(stacked, 1, 2560, 2520).source,
        const PixelRect(0, 1080, 2560, 1440),
      );
    });

    test('a lower-scale display is cropped at the capture scale and '
        'returned to its own pixel size', () {
      const monitors = [
        LogicalMonitor(x: 0, y: 0, width: 1280, height: 720, scaleFactor: 2),
        LogicalMonitor(x: 1280, y: 0, width: 1920, height: 1080),
      ];
      final hiDpi = crop(monitors, 0, 6400, 2160);
      expect(hiDpi.imageScale, 2);
      expect(hiDpi.source, const PixelRect(0, 0, 2560, 1440));
      expect((hiDpi.outputWidth, hiDpi.outputHeight), (2560, 1440));
      expect(hiDpi.resamples, isFalse);

      final normal = crop(monitors, 1, 6400, 2160);
      expect(normal.source, const PixelRect(2560, 0, 3840, 2160));
      expect((normal.outputWidth, normal.outputHeight), (1920, 1080));
      expect(normal.resamples, isTrue);
    });

    test('a 125% display maps logical pixels by the capture scale', () {
      // 2560x1440 at 125% is 2048x1152 logical; GDK reports scale 2.
      const single = [
        LogicalMonitor(x: 0, y: 0, width: 2048, height: 1152, scaleFactor: 2),
      ];
      final alone = crop(single, 0, 2560, 1440);
      expect(alone.imageScale, 1.25);
      expect(alone.source, const PixelRect(0, 0, 2560, 1440));
      expect((alone.outputWidth, alone.outputHeight), (2560, 1440));

      const mixed = [
        LogicalMonitor(x: 0, y: 0, width: 2048, height: 1152, scaleFactor: 2),
        LogicalMonitor(x: 2048, y: 0, width: 1920, height: 1080),
      ];
      expect(
        crop(mixed, 0, 4960, 1440).source,
        const PixelRect(0, 0, 2560, 1440),
      );
      final normal = crop(mixed, 1, 4960, 1440);
      expect(normal.source, const PixelRect(2560, 0, 2400, 1350));
      expect((normal.outputWidth, normal.outputHeight), (1920, 1080));
    });

    test('rounded edges tile neighbouring displays exactly', () {
      const monitors = [
        LogicalMonitor(x: 0, y: 0, width: 1280, height: 720, scaleFactor: 2),
        LogicalMonitor(x: 1280, y: 0, width: 1366, height: 768),
      ];
      final left = crop(monitors, 0, 3969, 1152).source;
      final right = crop(monitors, 1, 3969, 1152).source;
      expect(left, const PixelRect(0, 0, 1920, 1080));
      expect(right.left, left.left + left.width);
      expect(right.left + right.width, 3969);
    });

    test('a rotated display is already portrait in the logical layout', () {
      const monitors = [
        LogicalMonitor(x: 0, y: 0, width: 1080, height: 1920),
        LogicalMonitor(x: 1080, y: 240, width: 2560, height: 1440),
      ];
      expect(
        crop(monitors, 0, 3640, 1920).source,
        const PixelRect(0, 0, 1080, 1920),
      );
      expect(
        crop(monitors, 1, 3640, 1920).source,
        const PixelRect(1080, 240, 2560, 1440),
      );
    });

    test('a capture that does not fit the layout is rejected', () {
      const monitors = [
        LogicalMonitor(x: 0, y: 0, width: 2560, height: 1440),
        LogicalMonitor(x: 2560, y: 0, width: 1920, height: 1080),
      ];
      expect(
        () => crop(monitors, 1, 2560, 1440),
        throwsA(isA<DisplayLayoutMismatch>()),
      );
      expect(
        () => crop(monitors, 2, 4480, 1440),
        throwsA(isA<DisplayLayoutMismatch>()),
      );
      expect(
        () => crop(monitors, 0, 2240, 720),
        throwsA(isA<DisplayLayoutMismatch>()),
      );
      expect(
        () => crop(
          const [LogicalMonitor(x: 0, y: 0, width: 0, height: 1080)],
          0,
          1920,
          1080,
        ),
        throwsA(isA<DisplayLayoutMismatch>()),
      );
    });
  });

  group('DisplayPlacement.fromChannel', () {
    test('parses the runner reply', () {
      final placement = DisplayPlacement.fromChannel({
        'target': 1,
        'monitors': [
          {'x': 0, 'y': 0, 'width': 2560, 'height': 1440, 'scaleFactor': 1},
          {'x': 2560, 'y': 0, 'width': 1920, 'height': 1080, 'scaleFactor': 2},
        ],
      });
      expect(placement.targetIndex, 1);
      expect(placement.monitors[1].x, 2560);
      expect(placement.monitors[1].scaleFactor, 2);
    });

    test('rejects malformed replies', () {
      for (final reply in [
        null,
        'x',
        {'target': 0},
        {
          'target': 0,
          'monitors': [
            {'x': 0, 'y': 0, 'width': '1', 'height': 1, 'scaleFactor': 1},
          ],
        },
        {
          'target': 0,
          'monitors': [1],
        },
      ]) {
        expect(
          () => DisplayPlacement.fromChannel(reply),
          throwsFormatException,
          reason: '$reply',
        );
      }
    });
  });

  group('EngineFrameCodec', () {
    Future<Uint8List> twoColourPng() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 4, 2),
        ui.Paint()..color = const ui.Color(0xFFFF0000),
      );
      canvas.drawRect(
        const ui.Rect.fromLTWH(4, 0, 4, 2),
        ui.Paint()..color = const ui.Color(0xFF0000FF),
      );
      final image = await recorder.endRecording().toImage(8, 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    }

    Future<List<int>> pixels(OverlayFrame frame) async {
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      return data!.buffer.asUint8List();
    }

    test('crops exactly the target pixels and re-encodes them', () async {
      const codec = EngineFrameCodec();
      final decoded = await codec.decode(await twoColourPng());
      expect((decoded.width, decoded.height), (8, 2));

      final frame = await decoded.crop(
        const OverlayCrop(
          source: PixelRect(4, 0, 4, 2),
          outputWidth: 4,
          outputHeight: 2,
          imageScale: 1,
        ),
      );
      decoded.dispose();
      expect((frame.width, frame.height), (4, 2));
      final rgba = await pixels(frame);
      for (var i = 0; i < rgba.length; i += 4) {
        expect(rgba.sublist(i, i + 4), [0, 0, 255, 255]);
      }

      final png = await codec.encodePng(frame);
      expect(png.sublist(1, 4), 'PNG'.codeUnits);
      final again = await codec.decode(png);
      expect((again.width, again.height), (4, 2));
      again.dispose();
      frame.dispose();
    });

    test('downscales an upsampled display to its own size', () async {
      const codec = EngineFrameCodec();
      final decoded = await codec.decode(await twoColourPng());
      final frame = await decoded.crop(
        const OverlayCrop(
          source: PixelRect(0, 0, 4, 2),
          outputWidth: 2,
          outputHeight: 1,
          imageScale: 2,
        ),
      );
      decoded.dispose();
      expect((frame.width, frame.height), (2, 1));
      final rgba = await pixels(frame);
      expect(rgba.sublist(0, 4), [255, 0, 0, 255]);
      frame.dispose();
    });
  });
}
