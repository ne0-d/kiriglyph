import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/ui/workspace/fitted_image_geometry.dart';

TextRegion _box(String id, double l, double t, double r, double b) =>
    TextRegion(
      id: id,
      level: TextRegionLevel.line,
      text: id,
      polygon: [
        Point(x: l, y: t),
        Point(x: r, y: t),
        Point(x: r, y: b),
        Point(x: l, y: b),
      ],
      confidence: 1,
      readingOrder: 0,
    );

const _range = TextCharacterRange(
  start: 0,
  end: 1,
  text: 'r',
  polygon: [
    Point(x: 50, y: 10),
    Point(x: 60, y: 10),
    Point(x: 60, y: 30),
    Point(x: 50, y: 30),
  ],
  geometryKind: CharacterGeometryKind.derivedCtcPolygon,
  confidence: 1,
);

void main() {
  group('contain fit', () {
    test('a wide image is letterboxed vertically and centred', () {
      final geometry = FittedImageGeometry.contain(
        bounds: const Rect.fromLTWH(0, 0, 400, 400),
        imageSize: const Size(200, 100),
      );

      expect(geometry.destination, const Rect.fromLTWH(0, 100, 400, 200));
      expect(geometry.scale, 2);
    });

    test('a tall image is pillarboxed horizontally and centred', () {
      final geometry = FittedImageGeometry.contain(
        bounds: const Rect.fromLTWH(10, 20, 400, 200),
        imageSize: const Size(100, 200),
      );

      expect(geometry.destination, const Rect.fromLTWH(160, 20, 100, 200));
      expect(geometry.scale, 1);
    });

    test('the image is never stretched: aspect ratio is preserved', () {
      for (final bounds in const [
        Rect.fromLTWH(0, 0, 333, 777),
        Rect.fromLTWH(0, 0, 1280, 300),
        Rect.fromLTWH(5, 5, 90, 90),
      ]) {
        final geometry = FittedImageGeometry.contain(
          bounds: bounds,
          imageSize: const Size(640, 480),
        );

        expect(
          geometry.destination.width / geometry.destination.height,
          closeTo(640 / 480, 1e-9),
        );
        expect(bounds.contains(geometry.destination.topLeft), isTrue);
        expect(geometry.destination.width, lessThanOrEqualTo(bounds.width));
        expect(geometry.destination.height, lessThanOrEqualTo(bounds.height));
      }
    });

    test('degenerate bounds or image sizes produce an empty destination', () {
      expect(
        FittedImageGeometry.contain(
          bounds: Rect.zero,
          imageSize: const Size(10, 10),
        ).destination.isEmpty,
        isTrue,
      );
      expect(
        FittedImageGeometry.contain(
          bounds: const Rect.fromLTWH(0, 0, 100, 100),
          imageSize: Size.zero,
        ).destination.isEmpty,
        isTrue,
      );
    });
  });

  group('region mapping', () {
    final geometry = FittedImageGeometry.contain(
      bounds: const Rect.fromLTWH(0, 0, 400, 400),
      imageSize: const Size(200, 100),
    );

    test(
      'a region maps through the same destination rectangle as the image',
      () {
        final rect = geometry.regionRect(_box('r', 50, 10, 150, 30));

        expect(rect, const Rect.fromLTRB(100, 120, 300, 160));
      },
    );

    test('image corners map exactly onto the destination corners', () {
      expect(
        geometry.regionRect(_box('r', 0, 0, 200, 100)),
        geometry.destination,
      );
    });

    test('character ranges map and invert through the fitted image', () {
      expect(
        geometry.rangeRect(_range),
        const Rect.fromLTRB(100, 120, 120, 160),
      );
      final source = geometry.unmapPoint(const Offset(110, 140));
      expect(source.x, 55);
      expect(source.y, 20);
    });

    test('the mapping follows the image when the bounds are resized', () {
      final resized = FittedImageGeometry.contain(
        bounds: const Rect.fromLTWH(0, 0, 100, 100),
        imageSize: const Size(200, 100),
      );

      expect(
        resized.regionRect(_box('r', 50, 10, 150, 30)),
        const Rect.fromLTRB(25, 30, 75, 40),
      );
    });

    test('rotated polygons use their axis-aligned bounding box', () {
      const region = TextRegion(
        id: 'tilt',
        level: TextRegionLevel.line,
        text: 'tilt',
        polygon: [
          Point(x: 20, y: 10),
          Point(x: 60, y: 14),
          Point(x: 58, y: 30),
          Point(x: 18, y: 26),
        ],
        confidence: 1,
        readingOrder: 0,
      );

      expect(
        geometry.regionRect(region),
        const Rect.fromLTRB(36, 120, 120, 160),
      );
    });
  });

  group('hit targets', () {
    final geometry = FittedImageGeometry.contain(
      bounds: const Rect.fromLTWH(0, 0, 400, 400),
      imageSize: const Size(200, 100),
    );

    test('large regions are hit exactly where they are drawn', () {
      final region = _box('big', 50, 10, 150, 30);

      expect(geometry.hitRect(region), geometry.regionRect(region));
    });

    test('small regions grow to a usable target around their centre', () {
      final region = _box('tiny', 100, 50, 102, 52);
      final drawn = geometry.regionRect(region);

      final hit = geometry.hitRect(region);

      expect(hit.width, greaterThanOrEqualTo(FittedImageGeometry.minHitExtent));
      expect(
        hit.height,
        greaterThanOrEqualTo(FittedImageGeometry.minHitExtent),
      );
      expect(hit.center, drawn.center);
      expect(hit.contains(drawn.topLeft), isTrue);
      expect(hit.contains(drawn.bottomRight), isTrue);
    });

    test('growing the hit target does not change the drawn geometry', () {
      final region = _box('tiny', 100, 50, 102, 52);
      final before = geometry.regionRect(region);

      geometry.hitRect(region);

      expect(geometry.regionRect(region), before);
      expect(before, const Rect.fromLTRB(200, 200, 204, 204));
    });
  });
}
