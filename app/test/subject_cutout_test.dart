import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/export/subject_cutout.dart';
import 'package:kiriglyph/segmentation/subject_segmenter.dart';

void main() {
  test('crops to mask bounds and preserves opaque source colour', () {
    final source = _source(4, 3);
    final mask = _mask(4, 3, {
      const _P(1, 1): 255,
      const _P(2, 1): 255,
      const _P(1, 2): 255,
      const _P(2, 2): 255,
    });

    final cutout = const SubjectCutoutComposer().compose(
      source: source,
      mask: mask,
      result: _result(const SubjectRect(x: 1, y: 1, width: 2, height: 2)),
    );

    expect(cutout.sourceBounds, _rectEquals(1, 1, 2, 2));
    expect(cutout.width, 2);
    expect(cutout.height, 2);
    expect(_pixels(cutout.rgba), [
      [11, 12, 13, 255],
      [21, 22, 23, 255],
      [12, 13, 14, 255],
      [22, 23, 24, 255],
    ]);
  });

  test('padding expands crop without growing alpha', () {
    final cutout = const SubjectCutoutComposer(padding: 1).compose(
      source: _source(4, 4),
      mask: _mask(4, 4, {const _P(0, 0): 255}),
      result: _result(const SubjectRect(x: 0, y: 0, width: 1, height: 1)),
    );

    expect(cutout.sourceBounds, _rectEquals(0, 0, 2, 2));
    expect(_alphas(cutout.rgba), [255, 0, 0, 0]);
    expect(_pixels(cutout.rgba)[1].take(3), [0, 1, 2]);
  });

  test('partially transparent fringe is removed and decontaminated', () {
    final source = RgbaImageBuffer(
      width: 3,
      height: 1,
      rgba: Uint8List.fromList([
        250, 240, 230, 255, // bright subject interior
        20, 10, 0, 255, // dark background-coloured fringe
        0, 0, 0, 255,
      ]),
    );
    final mask = _mask(3, 1, {const _P(0, 0): 255, const _P(1, 0): 128});

    final cutout = const SubjectCutoutComposer().compose(
      source: source,
      mask: mask,
      result: _result(const SubjectRect(x: 0, y: 0, width: 2, height: 1)),
    );

    expect(_pixels(cutout.rgba), [
      [250, 240, 230, 255],
      [250, 240, 230, 0],
    ]);
  });

  test('rejects mask and source size mismatch with a typed error', () {
    expect(
      () => const SubjectCutoutComposer().compose(
        source: _source(2, 2),
        mask: _mask(3, 2, const {}),
        result: _result(const SubjectRect(x: 0, y: 0, width: 1, height: 1)),
      ),
      throwsA(
        isA<SubjectCutoutException>().having(
          (error) => error.kind,
          'kind',
          SubjectCutoutFailureKind.sizeMismatch,
        ),
      ),
    );
  });

  test('rejects invalid mask outcomes and empty opaque content', () {
    expect(
      () => const SubjectCutoutComposer().compose(
        source: _source(2, 2),
        mask: _mask(2, 2, const {}),
        result: _result(
          const SubjectRect(x: 0, y: 0, width: 1, height: 1),
          outcome: SubjectMaskOutcome.suspectFullImage,
        ),
      ),
      throwsA(
        isA<SubjectCutoutException>().having(
          (error) => error.kind,
          'kind',
          SubjectCutoutFailureKind.invalidMask,
        ),
      ),
    );

    expect(
      () => const SubjectCutoutComposer().compose(
        source: _source(2, 2),
        mask: _mask(2, 2, const {}),
        result: _result(const SubjectRect(x: 0, y: 0, width: 1, height: 1)),
      ),
      throwsA(
        isA<SubjectCutoutException>().having(
          (error) => error.kind,
          'kind',
          SubjectCutoutFailureKind.emptyMask,
        ),
      ),
    );
  });
}

RgbaImageBuffer _source(int width, int height) {
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      rgba[offset] = x * 10 + y;
      rgba[offset + 1] = x * 10 + y + 1;
      rgba[offset + 2] = x * 10 + y + 2;
      rgba[offset + 3] = 255;
    }
  }
  return RgbaImageBuffer(width: width, height: height, rgba: rgba);
}

RgbaImageBuffer _mask(int width, int height, Map<_P, int> alphas) {
  final rgba = Uint8List(width * height * 4);
  for (final entry in alphas.entries) {
    final offset = (entry.key.y * width + entry.key.x) * 4;
    rgba[offset] = entry.value;
    rgba[offset + 1] = entry.value;
    rgba[offset + 2] = entry.value;
    rgba[offset + 3] = 255;
  }
  return RgbaImageBuffer(width: width, height: height, rgba: rgba);
}

List<List<int>> _pixels(Uint8List rgba) => [
  for (var index = 0; index < rgba.length; index += 4)
    [rgba[index], rgba[index + 1], rgba[index + 2], rgba[index + 3]],
];

List<int> _alphas(Uint8List rgba) => [
  for (var index = 3; index < rgba.length; index += 4) rgba[index],
];

Matcher _rectEquals(int x, int y, int width, int height) => isA<SubjectRect>()
    .having((rect) => rect.x, 'x', x)
    .having((rect) => rect.y, 'y', y)
    .having((rect) => rect.width, 'width', width)
    .having((rect) => rect.height, 'height', height);

SubjectMaskResult _result(
  SubjectRect bounds, {
  SubjectMaskOutcome outcome = SubjectMaskOutcome.ok,
}) => SubjectMaskResult(
  imageWidth: 4,
  imageHeight: 4,
  mask: const SubjectMaskReference(
    path: '/tmp/mask.png',
    byteLength: 1,
    sha256: '0',
  ),
  bounds: bounds,
  stats: SubjectMaskStats(
    outcome: outcome,
    areaFraction: 0.25,
    bounds: bounds,
    touchesEdge: const SubjectEdgeTouches(
      left: false,
      top: false,
      right: false,
      bottom: false,
    ),
    components: SubjectComponentStats(count: 1, largestBounds: bounds),
  ),
  timings: const SubjectSegmentationTimings(promptMs: 1),
);

class _P {
  const _P(this.x, this.y);

  final int x;
  final int y;

  @override
  bool operator ==(Object other) => other is _P && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}
