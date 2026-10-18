import 'dart:math' as math;

import 'package:kiriglyph/ocr/ocr_result.dart';

/// A selection is text when this much of at least one OCR line box is inside.
const double selectionTextLineCoverageThreshold = 0.60;

/// A confident mask is an object when it fills more than this much selection.
const double selectionObjectFillThreshold = 0.25;

enum SelectionOutcomeKind { text, object, image }

class SelectionBounds {
  const SelectionBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => math.max(0, right - left);
  double get height => math.max(0, bottom - top);
  double get area => width * height;

  bool containsPoint(Point point) =>
      point.x >= left &&
      point.x <= right &&
      point.y >= top &&
      point.y <= bottom;
}

class SelectionMaskCandidate {
  const SelectionMaskCandidate({
    required this.confident,
    required this.areaFraction,
  });

  final bool confident;
  final double areaFraction;
}

class SelectionOutcome {
  const SelectionOutcome({
    required this.primary,
    required this.textLines,
    required this.canLiftObject,
    required this.canCopyScreenshot,
    required this.canSaveScreenshot,
  });

  final SelectionOutcomeKind primary;
  final List<TextRegion> textLines;
  final bool canLiftObject;
  final bool canCopyScreenshot;
  final bool canSaveScreenshot;
}

SelectionOutcome classifySelectionOutcome({
  required SelectionBounds selection,
  required Iterable<TextRegion> lines,
  SelectionMaskCandidate? mask,
}) {
  final selectedLines = [
    for (final line in lines)
      if (_lineCoverage(selection, line) >= selectionTextLineCoverageThreshold)
        line,
  ];
  final objectReachable =
      mask != null &&
      mask.confident &&
      mask.areaFraction > selectionObjectFillThreshold;
  final primary = selectedLines.isNotEmpty
      ? SelectionOutcomeKind.text
      : objectReachable
      ? SelectionOutcomeKind.object
      : SelectionOutcomeKind.image;
  return SelectionOutcome(
    primary: primary,
    textLines: List.unmodifiable(selectedLines),
    canLiftObject: objectReachable,
    canCopyScreenshot: selection.area > 0,
    canSaveScreenshot: selection.area > 0,
  );
}

double _lineCoverage(SelectionBounds selection, TextRegion line) {
  final bounds = _bounds(line.polygon);
  final intersectionLeft = math.max(selection.left, bounds.left);
  final intersectionTop = math.max(selection.top, bounds.top);
  final intersectionRight = math.min(selection.right, bounds.right);
  final intersectionBottom = math.min(selection.bottom, bounds.bottom);
  final intersectionWidth = math.max(0, intersectionRight - intersectionLeft);
  final intersectionHeight = math.max(0, intersectionBottom - intersectionTop);
  final lineArea = bounds.area;
  return lineArea <= 0
      ? 0
      : (intersectionWidth * intersectionHeight) / lineArea;
}

({double left, double top, double right, double bottom, double area}) _bounds(
  List<Point> points,
) {
  if (points.isEmpty) {
    return (left: 0, top: 0, right: 0, bottom: 0, area: 0);
  }
  var left = points.first.x;
  var top = points.first.y;
  var right = points.first.x;
  var bottom = points.first.y;
  for (final point in points.skip(1)) {
    left = math.min(left, point.x);
    top = math.min(top, point.y);
    right = math.max(right, point.x);
    bottom = math.max(bottom, point.y);
  }
  return (
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    area: math.max(0, right - left) * math.max(0, bottom - top),
  );
}
