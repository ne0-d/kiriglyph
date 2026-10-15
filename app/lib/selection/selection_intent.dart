import 'dart:math' as math;
import 'dart:ui';

import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/selection/freehand_selection_geometry.dart';

const int loopTextMinimumCharacters = 3;
const double loopTextMinimumAreaRatio = 0.12;
const double defaultTextHitTolerance = 3;

enum SelectionActiveKind { none, text, object }

enum LoopInterpretation { text, object }

class SelectionModifiers {
  const SelectionModifiers({
    this.shift = false,
    this.alt = false,
    this.secondary = false,
    this.control = false,
  });

  final bool shift;
  final bool alt;
  final bool secondary;
  final bool control;
}

sealed class SelectionIntent {
  const SelectionIntent();
}

class TextDragIntent extends SelectionIntent {
  const TextDragIntent();
}

class TextClickIntent extends SelectionIntent {
  const TextClickIntent({required this.clickCount});

  final int clickCount;
}

class ClearSelectionIntent extends SelectionIntent {
  const ClearSelectionIntent();
}

class ObjectClickIntent extends SelectionIntent {
  const ObjectClickIntent();
}

class ObjectAddForegroundIntent extends SelectionIntent {
  const ObjectAddForegroundIntent();
}

class ObjectAddBackgroundIntent extends SelectionIntent {
  const ObjectAddBackgroundIntent();
}

class LoopAsTextIntent extends SelectionIntent {
  const LoopAsTextIntent(this.metrics);

  final LoopClassificationMetrics metrics;
}

class LoopAsObjectIntent extends SelectionIntent {
  const LoopAsObjectIntent(this.metrics);

  final LoopClassificationMetrics metrics;
}

class LoopClassificationMetrics {
  const LoopClassificationMetrics({
    required this.interpretation,
    required this.characterCount,
    required this.textArea,
    required this.loopArea,
  });

  final LoopInterpretation interpretation;
  final int characterCount;
  final double textArea;
  final double loopArea;

  double get textAreaRatio => loopArea <= 0 ? 0 : textArea / loopArea;
}

SelectionIntent classifyPointerDownIntent({
  required bool startsOnText,
  required SelectionModifiers modifiers,
  required bool isClick,
  int clickCount = 1,
}) {
  if (modifiers.control) {
    if (!isClick) {
      return const LoopAsObjectIntent(
        LoopClassificationMetrics(
          interpretation: LoopInterpretation.object,
          characterCount: 0,
          textArea: 0,
          loopArea: 0,
        ),
      );
    }
    return _objectClickIntent(modifiers);
  }
  if (startsOnText) {
    return isClick
        ? (clickCount <= 1
              ? const ClearSelectionIntent()
              : TextClickIntent(clickCount: clickCount))
        : const TextDragIntent();
  }
  return isClick
      ? _objectClickIntent(modifiers)
      : const LoopAsObjectIntent(
          LoopClassificationMetrics(
            interpretation: LoopInterpretation.object,
            characterCount: 0,
            textArea: 0,
            loopArea: 0,
          ),
        );
}

SelectionIntent classifyLoopIntent({
  required Iterable<TextRegion> regions,
  required List<Point> stroke,
  bool forceObject = false,
}) {
  final metrics = classifyLoop(regions: regions, stroke: stroke);
  if (forceObject || metrics.interpretation == LoopInterpretation.object) {
    return LoopAsObjectIntent(
      LoopClassificationMetrics(
        interpretation: LoopInterpretation.object,
        characterCount: metrics.characterCount,
        textArea: metrics.textArea,
        loopArea: metrics.loopArea,
      ),
    );
  }
  return LoopAsTextIntent(metrics);
}

LoopClassificationMetrics classifyLoop({
  required Iterable<TextRegion> regions,
  required List<Point> stroke,
}) {
  final polygon = simplifyStroke(stroke, tolerance: 2);
  final loopArea = signedPolygonArea(polygon).abs();
  var characters = 0;
  var textArea = 0.0;
  if (polygon.length >= 3 && loopArea > 0) {
    for (final region in regions) {
      for (final range in region.ranges) {
        if (containsPointEvenOdd(polygon, characterRangeCenter(range))) {
          characters++;
          textArea += _polygonArea(range.polygon).abs();
        }
      }
    }
  }
  final ratio = loopArea <= 0 ? 0 : textArea / loopArea;
  final interpretation =
      characters >= loopTextMinimumCharacters &&
          ratio >= loopTextMinimumAreaRatio
      ? LoopInterpretation.text
      : LoopInterpretation.object;
  return LoopClassificationMetrics(
    interpretation: interpretation,
    characterCount: characters,
    textArea: textArea,
    loopArea: loopArea,
  );
}

bool pointIsOnRecognizedText({
  required Iterable<TextRegion> regions,
  required Point point,
  double tolerance = defaultTextHitTolerance,
}) {
  for (final region in regions) {
    if (_pointInInflatedPolygon(region.polygon, point, tolerance)) {
      return true;
    }
    for (final range in region.ranges) {
      if (_pointInInflatedPolygon(range.polygon, point, tolerance)) {
        return true;
      }
    }
  }
  return false;
}

SelectionIntent _objectClickIntent(SelectionModifiers modifiers) {
  if (modifiers.alt || modifiers.secondary) {
    return const ObjectAddBackgroundIntent();
  }
  if (modifiers.shift) {
    return const ObjectAddForegroundIntent();
  }
  return const ObjectClickIntent();
}

bool _pointInInflatedPolygon(
  List<Point> polygon,
  Point point,
  double tolerance,
) {
  if (containsPointEvenOdd(polygon, point)) {
    return true;
  }
  final bounds = _bounds(polygon).inflate(tolerance);
  return bounds.contains(_offset(point));
}

Rect _bounds(List<Point> points) {
  if (points.isEmpty) {
    return Rect.zero;
  }
  var left = points.first.x;
  var right = left;
  var top = points.first.y;
  var bottom = top;
  for (final point in points.skip(1)) {
    left = math.min(left, point.x);
    right = math.max(right, point.x);
    top = math.min(top, point.y);
    bottom = math.max(bottom, point.y);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

double _polygonArea(List<Point> points) => signedPolygonArea(points);

Offset _offset(Point point) => Offset(point.x, point.y);
