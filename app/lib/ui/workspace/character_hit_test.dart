import 'package:flutter/foundation.dart';

import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/selection/region_selection.dart';

@immutable
class CharacterHit {
  const CharacterHit({
    required this.region,
    required this.range,
    required this.position,
  });

  final TextRegion region;
  final TextCharacterRange range;
  final TextPosition position;
}

/// Resolves source-image points against validated character polygons.
class CharacterHitTest {
  CharacterHitTest(Iterable<TextRegion> regions)
    : _regions = (regions.toList()
        ..sort((first, second) {
          return first.readingOrder.compareTo(second.readingOrder);
        }));

  final List<TextRegion> _regions;

  CharacterHit? hit(Point point) {
    for (final region in _regions) {
      for (final range in region.ranges) {
        if (_contains(point, range.polygon)) {
          return _hit(region, range, point);
        }
      }
    }
    return null;
  }

  CharacterHit nearest(Point point) {
    final direct = hit(point);
    if (direct != null) {
      return direct;
    }
    TextRegion? bestLine;
    var bestDistance = double.infinity;
    for (final region in _regions) {
      if (region.ranges.isEmpty) {
        continue;
      }
      final distance = _distanceToPolygonSquared(point, region.polygon);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestLine = region;
      }
    }
    if (bestLine == null) {
      throw StateError('no validated character geometry');
    }
    var bestRange = bestLine.ranges.first;
    bestDistance = double.infinity;
    for (final range in bestLine.ranges) {
      final distance = _distanceToPolygonSquared(point, range.polygon);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestRange = range;
      }
    }
    return _hit(bestLine, bestRange, point);
  }

  CharacterHit _hit(TextRegion region, TextCharacterRange range, Point point) {
    final left = Point(
      x: (range.polygon[0].x + range.polygon[3].x) / 2,
      y: (range.polygon[0].y + range.polygon[3].y) / 2,
    );
    final right = Point(
      x: (range.polygon[1].x + range.polygon[2].x) / 2,
      y: (range.polygon[1].y + range.polygon[2].y) / 2,
    );
    final directionX = right.x - left.x;
    final directionY = right.y - left.y;
    final lengthSquared = directionX * directionX + directionY * directionY;
    final amount = lengthSquared == 0
        ? 0.0
        : ((point.x - left.x) * directionX + (point.y - left.y) * directionY) /
              lengthSquared;
    final offset = amount < 0.5 ? range.start : range.end;
    return CharacterHit(
      region: region,
      range: range,
      position: TextPosition(regionId: region.id, offset: offset),
    );
  }

  static double _distanceToPolygonSquared(Point point, List<Point> polygon) {
    if (_contains(point, polygon)) {
      return 0;
    }
    var best = double.infinity;
    for (var index = 0; index < polygon.length; index++) {
      final distance = _distanceToSegmentSquared(
        point,
        polygon[index],
        polygon[(index + 1) % polygon.length],
      );
      if (distance < best) {
        best = distance;
      }
    }
    return best;
  }

  static double _distanceToSegmentSquared(Point point, Point start, Point end) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) {
      final pointDx = point.x - start.x;
      final pointDy = point.y - start.y;
      return pointDx * pointDx + pointDy * pointDy;
    }
    final amount =
        (((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared)
            .clamp(0.0, 1.0);
    final nearestX = start.x + amount * dx;
    final nearestY = start.y + amount * dy;
    final pointDx = point.x - nearestX;
    final pointDy = point.y - nearestY;
    return pointDx * pointDx + pointDy * pointDy;
  }

  static bool _contains(Point point, List<Point> polygon) {
    bool? sign;
    for (var index = 0; index < polygon.length; index++) {
      final first = polygon[index];
      final second = polygon[(index + 1) % polygon.length];
      final cross =
          (second.x - first.x) * (point.y - first.y) -
          (second.y - first.y) * (point.x - first.x);
      if (cross.abs() <= 1e-9) {
        continue;
      }
      final current = cross > 0;
      if (sign != null && sign != current) {
        return false;
      }
      sign = current;
    }
    return true;
  }
}
