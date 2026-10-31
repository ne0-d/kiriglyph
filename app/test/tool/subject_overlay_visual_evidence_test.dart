import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/segmentation/subject_segmenter.dart';
import 'package:kiriglyph/selection/rectangle_selection.dart';
import 'package:kiriglyph/selection/subject_prompt_state.dart';
import 'package:kiriglyph/ui/overlay/overlay_toolbar.dart';
import 'package:kiriglyph/ui/overlay/subject_mask_alpha.dart';
import 'package:kiriglyph/ui/overlay/subject_overlay_layer.dart';
import 'package:kiriglyph/ui/workspace/fitted_image_geometry.dart';

/// A desktop screenshot to draw the evidence on. The test skips itself
/// without one: set KIRIGLYPH_EVIDENCE_IMAGE to the path of a JPEG or PNG.
final _screenshotPath = Platform.environment['KIRIGLYPH_EVIDENCE_IMAGE'] ?? '';
const _outDir = '/tmp/kiriglyph-ui';
const _shotKey = Key('visual-evidence-boundary');

void main() {
  testWidgets('writes Subject overlay visual evidence', (tester) async {
    final source = File(_screenshotPath);
    if (!source.existsSync()) {
      markTestSkipped('desktop screenshot fixture is not available');
      return;
    }
    final frame = await tester.runAsync(
      () async => decodeImageFromList(await source.readAsBytes()),
    );
    final image = frame!;
    addTearDown(image.dispose);
    final size = Size(image.width.toDouble(), image.height.toDouble());
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final geometry = FittedImageGeometry.contain(
      bounds: Offset.zero & size,
      imageSize: size,
    );
    final bounds = SubjectRect(
      x: (image.width * 0.68).round(),
      y: (image.height * 0.40).round(),
      width: (image.width * 0.23).round(),
      height: (image.height * 0.34).round(),
    );
    final result = _result(
      width: image.width,
      height: image.height,
      bounds: bounds,
    );
    final trueAlpha = (await tester.runAsync(
      () => _maskImage(image.width, image.height, legacy: false),
    ))!;
    final legacy = (await tester.runAsync(
      () => _maskImage(image.width, image.height, legacy: true),
    ))!;
    addTearDown(trueAlpha.dispose);
    addTearDown(legacy.dispose);

    final cases = [
      (
        'unified-object-popped-true-alpha.png',
        trueAlpha,
        result,
        'Subject selected',
        false,
        false,
        1.0,
        Brightness.dark,
      ),
      (
        'unified-object-popped-legacy-gray.png',
        legacy,
        result,
        'Subject selected',
        false,
        false,
        1.0,
        Brightness.dark,
      ),
      (
        'unified-object-edge-note.png',
        trueAlpha,
        _result(
          width: image.width,
          height: image.height,
          bounds: bounds,
          edge: true,
        ),
        'Subject touches the screen edge',
        false,
        false,
        1.0,
        Brightness.dark,
      ),
      (
        'unified-object-exporting.png',
        trueAlpha,
        result,
        'Subject selected',
        true,
        false,
        1.0,
        Brightness.dark,
      ),
      (
        'unified-object-high-contrast.png',
        trueAlpha,
        result,
        'Subject selected',
        false,
        true,
        1.0,
        Brightness.dark,
      ),
      (
        'unified-object-text-scale-2.png',
        trueAlpha,
        result,
        'Subject selected',
        false,
        false,
        2.0,
        Brightness.light,
      ),
    ];

    for (final entry in cases) {
      final (
        name,
        mask,
        maskResult,
        status,
        exporting,
        highContrast,
        textScale,
        brightness,
      ) = entry;
      await _pumpEvidence(
        tester,
        frame: image,
        geometry: geometry,
        mask: mask,
        result: maskResult,
        chipStatus: status,
        exporting: exporting,
        highContrast: highContrast,
        textScale: textScale,
        brightness: brightness,
      );
      await tester.runAsync(() => _writePng(tester, name));
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}

Future<void> _pumpEvidence(
  WidgetTester tester, {
  required ui.Image frame,
  required FittedImageGeometry geometry,
  required ui.Image mask,
  required SubjectMaskResult result,
  required String chipStatus,
  required bool exporting,
  required bool highContrast,
  required double textScale,
  required Brightness brightness,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        colorSchemeSeed: const Color(0xFFE95420),
      ),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(frame.width.toDouble(), frame.height.toDouble()),
          textScaler: TextScaler.linear(textScale),
          highContrast: highContrast,
        ),
        child: RepaintBoundary(
          key: _shotKey,
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RawImage(image: frame, fit: BoxFit.fill),
                SubjectOverlayLayer(
                  geometry: geometry,
                  imageWidth: frame.width,
                  imageHeight: frame.height,
                  promptState: const SubjectPromptState(),
                  maskImage: CanonicalSubjectMask(
                    image: mask,
                    decodeDuration: Duration.zero,
                  ),
                  maskResult: result,
                  onPromptChanged: (_) {},
                ),
                Positioned(
                  right: 16,
                  top: textScale > 1.5
                      ? math.max(16, geometry.destination.height * 0.54)
                      : math.max(16, geometry.destination.height * 0.70),
                  child: SubjectActionChip(
                    status: chipStatus,
                    exporting: exporting,
                    onCopy: () {},
                    onSave: () {},
                    onRemove: () {},
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: OverlayToolbar(
                      status: 'Drag across text, or click an object',
                      onCopy: null,
                      onCopyAll: null,
                      tool: SelectionTool.rectangle,
                      onToolChanged: (_) {},
                      onSaveFullScreenshot: null,
                      onClose: () {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<ui.Image> _maskImage(int width, int height, {required bool legacy}) {
  final rgba = Uint8List(width * height * 4);
  final centerX = width * 0.79;
  final centerY = height * 0.56;
  final radiusX = width * 0.105;
  final radiusY = height * 0.18;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = (y * width + x) * 4;
      final inside =
          math.pow((x - centerX) / radiusX, 2) +
              math.pow((y - centerY) / radiusY, 2) <=
          1;
      if (legacy) {
        final gray = inside ? 255 : 0;
        rgba[index] = gray;
        rgba[index + 1] = gray;
        rgba[index + 2] = gray;
        rgba[index + 3] = 255;
      } else {
        rgba[index] = 255;
        rgba[index + 1] = 255;
        rgba[index + 2] = 255;
        rgba[index + 3] = inside ? 255 : 0;
      }
    }
  }
  final canonical = canonicalSubjectMaskRgba(rgba);
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    canonical,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

Future<void> _writePng(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_shotKey),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final directory = Directory(_outDir)..createSync(recursive: true);
  await File('${directory.path}/$name').writeAsBytes(
    bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
}

SubjectMaskResult _result({
  required int width,
  required int height,
  required SubjectRect bounds,
  bool edge = false,
}) => SubjectMaskResult(
  imageWidth: width,
  imageHeight: height,
  mask: const SubjectMaskReference(path: '', byteLength: 0, sha256: ''),
  bounds: bounds,
  stats: SubjectMaskStats(
    outcome: SubjectMaskOutcome.ok,
    areaFraction: 0.12,
    bounds: bounds,
    touchesEdge: SubjectEdgeTouches(
      left: edge,
      top: false,
      right: false,
      bottom: false,
    ),
    components: SubjectComponentStats(count: 1, largestBounds: bounds),
  ),
  timings: const SubjectSegmentationTimings(promptMs: 1),
);
