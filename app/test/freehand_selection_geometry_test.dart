import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/selection/freehand_selection_geometry.dart';

import 'support/workspace_harness.dart';

List<Point> _polygon(List<(double x, double y)> points) => [
  for (final point in points) Point(x: point.$1, y: point.$2),
];

TextCharacterRange _tiltedCharacter(
  int index,
  String text,
  List<(double x, double y)> polygon,
) => TextCharacterRange(
  start: index,
  end: index + 1,
  text: text,
  polygon: _polygon(polygon),
  geometryKind: CharacterGeometryKind.derivedCtcPolygon,
  confidence: 1,
);

TextRegion _textLine(
  String id,
  String text,
  int order,
  double left,
  double top,
) => box(
  id,
  text,
  order,
  left,
  top,
  left + text.length * 10,
  top + 20,
  ranges: [
    for (var index = 0; index < text.length; index++)
      character(
        index,
        text[index],
        left + index * 10,
        top,
        left + index * 10 + 10,
        top + 20,
      ),
  ],
);

void main() {
  group('point in freehand polygon', () {
    test('uses even-odd containment for concave polygons', () {
      final polygon = _polygon([(0, 0), (40, 0), (40, 40), (20, 20), (0, 40)]);

      expect(containsPointEvenOdd(polygon, const Point(x: 30, y: 10)), isTrue);
      expect(containsPointEvenOdd(polygon, const Point(x: 20, y: 32)), isFalse);
    });

    test('handles self-intersecting figure-eight strokes by parity', () {
      final polygon = _polygon([(0, 0), (40, 40), (0, 40), (40, 0)]);

      expect(containsPointEvenOdd(polygon, const Point(x: 10, y: 30)), isTrue);
      expect(containsPointEvenOdd(polygon, const Point(x: 30, y: 10)), isTrue);
      expect(
        containsPointEvenOdd(polygon, const Point(x: 20, y: 20)),
        isTrue,
        reason: 'points on the stroke boundary count as inside',
      );
    });
  });

  group('stroke selection', () {
    test('selects center-inside characters across multiple lines', () {
      final ranges = selectCharacterRangesInsideStroke(
        regions: multilineCharacterResult().regions,
        stroke: _polygon([(10, 0), (70, 0), (70, 70), (10, 70)]),
      );

      expect(ranges, {'l1': (0, 2), 'l2': (0, 2)});
    });

    test('selects tilted line characters by geometry center', () {
      final region = box(
        'tilt',
        'ab',
        0,
        10,
        10,
        70,
        40,
        ranges: [
          _tiltedCharacter(0, 'a', [(10, 10), (30, 12), (28, 32), (8, 30)]),
          _tiltedCharacter(1, 'b', [(30, 12), (50, 14), (48, 34), (28, 32)]),
        ],
      );

      final ranges = selectCharacterRangesInsideStroke(
        regions: [region],
        stroke: _polygon([(5, 5), (35, 5), (35, 45), (5, 45)]),
      );

      expect(ranges, {'tilt': (0, 2)});
    });

    test('empty circles return no ranges', () {
      final ranges = selectCharacterRangesInsideStroke(
        regions: characterSampleResult().regions,
        stroke: _polygon([(120, 60), (160, 60), (160, 90), (120, 90)]),
      );

      expect(ranges, isEmpty);
    });

    test('too-short strokes are ignored', () {
      final stroke = _polygon([(0, 0), (4, 0), (4, 1), (0, 1)]);

      expect(isUsableFreehandStroke(stroke), isFalse);
      expect(
        selectCharacterRangesInsideStroke(
          regions: characterSampleResult().regions,
          stroke: stroke,
        ),
        isEmpty,
      );
    });

    test('source-coordinate testing is independent of viewport zoom', () {
      final sourceStroke = _polygon([(31, 0), (89, 0), (89, 40), (31, 40)]);

      final ranges = selectCharacterRangesInsideStroke(
        regions: characterSampleResult().regions,
        stroke: sourceStroke,
      );

      expect(ranges, {'l1': (0, 4)});
    });

    test('loose circle over half a paragraph selects all of it', () {
      final regions = [
        _textLine('a', 'abcdefghij', 0, 20, 10),
        _textLine('b', 'klmnopqrst', 1, 20, 35),
        _textLine('c', 'uvwxyzabcd', 2, 20, 60),
      ];

      final ranges = selectCharacterRangesInsideStroke(
        regions: regions,
        stroke: _polygon([(10, 0), (85, 0), (85, 90), (10, 90)]),
      );

      expect(ranges, {'a': (0, 10), 'b': (0, 10), 'c': (0, 10)});
    });

    test('circle over two paragraphs partly selects both paragraphs', () {
      final regions = [
        _textLine('a1', 'aaaaaaaaaa', 0, 20, 10),
        _textLine('a2', 'bbbbbbbbbb', 1, 20, 35),
        _textLine('b1', 'cccccccccc', 2, 20, 90),
        _textLine('b2', 'dddddddddd', 3, 20, 115),
      ];

      final ranges = selectCharacterRangesInsideStroke(
        regions: regions,
        stroke: _polygon([(10, 20), (85, 20), (85, 130), (10, 130)]),
      );

      expect(ranges, {
        'a1': (0, 10),
        'a2': (0, 10),
        'b1': (0, 10),
        'b2': (0, 10),
      });
    });

    test('barely touching a neighbouring paragraph does not select it', () {
      final regions = [
        _textLine('a', 'aaaaaaaaaa', 0, 20, 10),
        _textLine('b', 'bbbbbbbbbb', 1, 20, 70),
      ];

      final ranges = selectCharacterRangesInsideStroke(
        regions: regions,
        stroke: _polygon([(10, 0), (125, 0), (125, 42), (10, 42)]),
      );

      expect(ranges, {'a': (0, 10)});
    });

    test('falls back to line extent below snapping thresholds', () {
      final regions = [_textLine('a', 'abcdefghij', 0, 20, 10)];

      final ranges = selectCharacterRangesInsideStroke(
        regions: regions,
        stroke: _polygon([(36, 5), (54, 5), (54, 35), (36, 35)]),
      );

      expect(ranges, {'a': (2, 3)});
    });
  });
}
