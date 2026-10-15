import 'dart:math' as math;

import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/selection/paragraph_grouping.dart';

const double defaultFreehandMinimumPathLength = 12;
const double defaultFreehandMinimumArea = 1;
const double paragraphSnapCharacterFractionThreshold = 0.2;
const double paragraphSnapCompleteLineFraction = 1.0;
const double lineSnapCharacterFractionThreshold = 0.5;

typedef LineSelectionRanges = Map<String, (int, int)>;

/// Geometry helpers for selecting text with a closed freehand stroke.
///
/// A released stroke is treated as an even-odd polygon. That keeps
/// self-intersecting shapes intuitive: a figure-eight selects characters in
/// either lobe while the overlap parity still follows normal path fill rules.
LineSelectionRanges selectCharacterRangesInsideStroke({
  required Iterable<TextRegion> regions,
  required List<Point> stroke,
  List<TextParagraph>? paragraphs,
  double simplificationTolerance = 2,
}) {
  if (!isUsableFreehandStroke(stroke)) {
    return const {};
  }

  final polygon = simplifyStroke(stroke, tolerance: simplificationTolerance);
  if (polygon.length < 3) {
    return const {};
  }

  final orderedRegions = regions.toList();
  final paragraphGroups = paragraphs ?? groupTextParagraphs(orderedRegions);
  final insideByRegion = {
    for (final region in orderedRegions)
      region.id: _insideCharacters(region, polygon),
  };
  final regionById = {for (final region in orderedRegions) region.id: region};
  final ranges = <String, (int start, int end)>{};

  for (final paragraph in paragraphGroups) {
    final paragraphRegions = [
      for (final id in paragraph.regionIds)
        if (regionById[id] != null) regionById[id]!,
    ];
    final insideCount = paragraphRegions.fold<int>(
      0,
      (total, region) => total + (insideByRegion[region.id]?.length ?? 0),
    );
    if (insideCount == 0) {
      continue;
    }
    final totalCount = paragraphRegions.fold<int>(
      0,
      (total, region) => total + _selectableCharacterCount(region),
    );
    final paragraphFraction = totalCount == 0 ? 0 : insideCount / totalCount;
    final hasCompleteLine = paragraphRegions.any((region) {
      final lineTotal = _selectableCharacterCount(region);
      final lineInside = insideByRegion[region.id]?.length ?? 0;
      return lineTotal > 0 &&
          lineInside / lineTotal >= paragraphSnapCompleteLineFraction;
    });

    if (paragraphFraction >= paragraphSnapCharacterFractionThreshold ||
        hasCompleteLine) {
      for (final region in paragraphRegions) {
        final length = region.text.runes.length;
        if (length > 0) {
          ranges[region.id] = (0, length);
        }
      }
      continue;
    }

    for (final region in paragraphRegions) {
      final inside = insideByRegion[region.id] ?? const <TextCharacterRange>[];
      if (inside.isEmpty) {
        continue;
      }
      final lineTotal = _selectableCharacterCount(region);
      if (lineTotal > 0 &&
          inside.length / lineTotal >= lineSnapCharacterFractionThreshold) {
        ranges[region.id] = (0, region.text.runes.length);
      } else {
        final extent = _extentForRanges(inside);
        if (extent != null) {
          ranges[region.id] = extent;
        }
      }
    }
  }
  return ranges;
}

List<TextCharacterRange> _insideCharacters(
  TextRegion region,
  List<Point> polygon,
) => [
  for (final range in region.ranges)
    if (containsPointEvenOdd(polygon, characterRangeCenter(range))) range,
];

(int, int)? _extentForRanges(List<TextCharacterRange> ranges) {
  int? first;
  int? last;
  for (final range in ranges) {
    first = first == null ? range.start : math.min(first, range.start);
    last = last == null ? range.end : math.max(last, range.end);
  }
  return first == null || last == null || first >= last ? null : (first, last);
}

int _selectableCharacterCount(TextRegion region) =>
    region.ranges.isNotEmpty ? region.ranges.length : region.text.runes.length;

bool isUsableFreehandStroke(
  List<Point> points, {
  double minPathLength = defaultFreehandMinimumPathLength,
  double minArea = defaultFreehandMinimumArea,
}) {
  return points.length >= 3 &&
      pathLength(points) >= minPathLength &&
      signedPolygonArea(points).abs() >= minArea;
}

double pathLength(List<Point> points) {
  var length = 0.0;
  for (var index = 1; index < points.length; index++) {
    length += _distance(points[index - 1], points[index]);
  }
  return length;
}

double signedPolygonArea(List<Point> points) {
  if (points.length < 3) {
    return 0;
  }
  var sum = 0.0;
  for (var index = 0; index < points.length; index++) {
    final first = points[index];
    final second = points[(index + 1) % points.length];
    sum += first.x * second.y - second.x * first.y;
  }
  return sum / 2;
}

Point characterRangeCenter(TextCharacterRange range) {
  var x = 0.0;
  var y = 0.0;
  for (final point in range.polygon) {
    x += point.x;
    y += point.y;
  }
  final count = range.polygon.isEmpty ? 1 : range.polygon.length;
  return Point(x: x / count, y: y / count);
}

bool containsPointEvenOdd(List<Point> polygon, Point point) {
  if (polygon.length < 3) {
    return false;
  }
  var inside = false;
  for (
    var index = 0, previous = polygon.length - 1;
    index < polygon.length;
    previous = index++
  ) {
    final a = polygon[previous];
    final b = polygon[index];
    if (_pointOnSegment(point, a, b)) {
      return true;
    }
    final crosses = (a.y > point.y) != (b.y > point.y);
    if (crosses) {
      final x = (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x;
      if (point.x < x) {
        inside = !inside;
      }
    }
  }
  return inside;
}

List<Point> simplifyStroke(List<Point> points, {required double tolerance}) {
  if (points.length <= 2 || tolerance <= 0) {
    return List<Point>.unmodifiable(points);
  }
  final keep = List<bool>.filled(points.length, false)
    ..[0] = true
    ..[points.length - 1] = true;
  _simplifySection(points, keep, 0, points.length - 1, tolerance * tolerance);
  return [
    for (var index = 0; index < points.length; index++)
      if (keep[index]) points[index],
  ];
}

void _simplifySection(
  List<Point> points,
  List<bool> keep,
  int start,
  int end,
  double toleranceSquared,
) {
  if (end <= start + 1) {
    return;
  }
  var bestDistance = 0.0;
  var bestIndex = start;
  for (var index = start + 1; index < end; index++) {
    final distance = _distanceToSegmentSquared(
      points[index],
      points[start],
      points[end],
    );
    if (distance > bestDistance) {
      bestDistance = distance;
      bestIndex = index;
    }
  }
  if (bestDistance <= toleranceSquared) {
    return;
  }
  keep[bestIndex] = true;
  _simplifySection(points, keep, start, bestIndex, toleranceSquared);
  _simplifySection(points, keep, bestIndex, end, toleranceSquared);
}

double _distance(Point first, Point second) {
  final dx = first.x - second.x;
  final dy = first.y - second.y;
  return math.sqrt(dx * dx + dy * dy);
}

bool _pointOnSegment(Point point, Point start, Point end) =>
    _distanceToSegmentSquared(point, start, end) <= 1e-9;

double _distanceToSegmentSquared(Point point, Point start, Point end) {
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
