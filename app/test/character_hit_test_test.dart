import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/ui/workspace/character_hit_test.dart';

TextCharacterRange _range(int start, double left, double right) =>
    TextCharacterRange(
      start: start,
      end: start + 1,
      text: String.fromCharCode(97 + start),
      polygon: [
        Point(x: left, y: 10),
        Point(x: right, y: 10),
        Point(x: right, y: 30),
        Point(x: left, y: 30),
      ],
      geometryKind: CharacterGeometryKind.derivedCtcPolygon,
      confidence: 1,
    );

TextRegion _line() => TextRegion(
  id: 'line',
  level: TextRegionLevel.line,
  text: 'ab',
  polygon: const [
    Point(x: 10, y: 10),
    Point(x: 50, y: 10),
    Point(x: 50, y: 30),
    Point(x: 10, y: 30),
  ],
  confidence: 1,
  readingOrder: 0,
  ranges: [_range(0, 10, 30), _range(1, 30, 50)],
);

void main() {
  test('resolves leading and trailing character boundaries', () {
    final hitTest = CharacterHitTest([_line()]);

    expect(hitTest.hit(const Point(x: 12, y: 20))?.position.offset, 0);
    expect(hitTest.hit(const Point(x: 28, y: 20))?.position.offset, 1);
    expect(hitTest.hit(const Point(x: 32, y: 20))?.position.offset, 1);
    expect(hitTest.hit(const Point(x: 48, y: 20))?.position.offset, 2);
  });

  test('does not start a selection in empty image space', () {
    final hitTest = CharacterHitTest([_line()]);

    expect(hitTest.hit(const Point(x: 80, y: 80)), isNull);
  });

  test('drag continuation resolves the nearest character boundary', () {
    final hitTest = CharacterHitTest([_line()]);

    final hit = hitTest.nearest(const Point(x: 80, y: 40));

    expect(hit.position.regionId, 'line');
    expect(hit.position.offset, 2);
  });
}
