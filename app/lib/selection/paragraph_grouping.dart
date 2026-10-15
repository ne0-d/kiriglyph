import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/selection/region_selection.dart';

const double paragraphMaxVerticalGapHeightRatio = 0.9;
const double paragraphMaxLineHeightRatio = 1.5;
const double paragraphMinHorizontalOverlapRatio = 0.35;
const double paragraphLeftAlignmentToleranceHeightRatio = 1.5;
const double paragraphMaxContinuationIndentHeightRatio = 4.0;

@immutable
class TextParagraph {
  const TextParagraph({
    required this.regionIds,
    required this.totalCharacterCount,
  });

  final List<String> regionIds;
  final int totalCharacterCount;
}

List<TextParagraph> groupTextParagraphs(Iterable<TextRegion> regions) {
  final orderedEntries = regions.toList().asMap().entries.toList()
    ..sort((first, second) {
      final byOrder = first.value.readingOrder.compareTo(
        second.value.readingOrder,
      );
      return byOrder != 0 ? byOrder : first.key.compareTo(second.key);
    });
  final ordered = orderedEntries.map((entry) => entry.value).toList();
  if (ordered.isEmpty) {
    return const [];
  }

  final metrics = {
    for (final region in ordered) region.id: _LineMetrics(region),
  };
  final paragraphs = <TextParagraph>[];
  var current = <TextRegion>[ordered.first];
  for (final next in ordered.skip(1)) {
    final previous = current.last;
    if (_belongsWithPrevious(metrics[previous.id]!, metrics[next.id]!)) {
      current.add(next);
    } else {
      paragraphs.add(_paragraph(current));
      current = [next];
    }
  }
  paragraphs.add(_paragraph(current));
  return List.unmodifiable(paragraphs);
}

/// Keyboard selection by whole paragraphs.
///
/// Without a selection, [direction] 1 selects the first paragraph and -1 the
/// last. A selection that does not yet cover whole paragraphs first snaps to
/// the paragraphs it touches; after that each call adds the neighbouring
/// paragraph in [direction]. Reaching either end leaves the selection as it
/// is.
RegionSelection extendSelectionByParagraph(
  RegionSelection selection,
  List<TextParagraph> paragraphs, {
  required int direction,
}) {
  if (direction == 0) {
    return selection;
  }
  final regionById = {
    for (final region in selection.regions) region.id: region,
  };
  // Lines with text only, so empty lines never block the keyboard.
  final units = [
    for (final paragraph in paragraphs)
      [
        for (final id in paragraph.regionIds)
          if (regionById[id]?.text.runes.isNotEmpty ?? false) regionById[id]!,
      ],
  ].where((lines) => lines.isNotEmpty).toList();
  if (units.isEmpty) {
    return selection;
  }

  bool isSelected(TextRegion region) {
    final range = selection.selectedRangeFor(region.id);
    return range != null && range.$1 < range.$2;
  }

  bool isWhole(TextRegion region) {
    final range = selection.selectedRangeFor(region.id);
    return range != null &&
        range.$1 == 0 &&
        range.$2 == region.text.runes.length;
  }

  final touched = [
    for (var index = 0; index < units.length; index++)
      if (units[index].any(isSelected)) index,
  ];
  late int first;
  late int last;
  if (touched.isEmpty) {
    first = last = direction > 0 ? 0 : units.length - 1;
  } else {
    first = touched.first;
    last = touched.last;
    final complete = units
        .sublist(first, last + 1)
        .every((lines) => lines.every(isWhole));
    if (complete) {
      if (direction > 0 && last + 1 < units.length) {
        last++;
      } else if (direction < 0 && first > 0) {
        first--;
      } else {
        return selection;
      }
    }
  }
  return selection.selectLineRanges({
    for (final lines in units.sublist(first, last + 1))
      for (final region in lines) region.id: (0, region.text.runes.length),
  });
}

String selectedTextWithParagraphSeparators(
  RegionSelection selection,
  List<TextParagraph> paragraphs,
) {
  if (!selection.hasSelection || selection.selectedRegions.isEmpty) {
    return selection.selectedText;
  }
  final paragraphByRegion = <String, int>{};
  for (var index = 0; index < paragraphs.length; index++) {
    for (final id in paragraphs[index].regionIds) {
      paragraphByRegion[id] = index;
    }
  }

  final buffer = StringBuffer();
  int? previousParagraph;
  var wroteLine = false;
  for (final region in selection.regions) {
    final range = selection.selectedRangeFor(region.id);
    if (range == null || range.$1 >= range.$2) {
      continue;
    }
    if (wroteLine) {
      final paragraph = paragraphByRegion[region.id];
      buffer.write(
        paragraph != null &&
                previousParagraph != null &&
                paragraph != previousParagraph
            ? '\n\n'
            : '\n',
      );
    }
    final codePoints = region.text.runes.toList(growable: false);
    buffer.write(String.fromCharCodes(codePoints.sublist(range.$1, range.$2)));
    previousParagraph = paragraphByRegion[region.id];
    wroteLine = true;
  }
  return buffer.toString();
}

TextParagraph _paragraph(List<TextRegion> regions) => TextParagraph(
  regionIds: List.unmodifiable(regions.map((region) => region.id)),
  totalCharacterCount: regions.fold(
    0,
    (total, region) =>
        total +
        (region.ranges.isNotEmpty ? region.ranges.length : region.text.length),
  ),
);

bool _belongsWithPrevious(_LineMetrics previous, _LineMetrics next) {
  final smallerHeight = math.min(previous.height, next.height);
  if (smallerHeight <= 0) {
    return false;
  }
  if (previous.verticalGapTo(next) >
      paragraphMaxVerticalGapHeightRatio * smallerHeight) {
    return false;
  }
  if (math.max(previous.height, next.height) / smallerHeight >
      paragraphMaxLineHeightRatio) {
    return false;
  }
  if (previous.horizontalOverlapRatio(next) <
      paragraphMinHorizontalOverlapRatio) {
    return false;
  }
  final leftDelta = next.left - previous.left;
  if (leftDelta.abs() <=
      paragraphLeftAlignmentToleranceHeightRatio * smallerHeight) {
    return true;
  }
  return leftDelta > 0 &&
      leftDelta <= paragraphMaxContinuationIndentHeightRatio * smallerHeight;
}

class _LineMetrics {
  _LineMetrics(TextRegion region)
    : left = region.polygon.map((point) => point.x).reduce(math.min),
      right = region.polygon.map((point) => point.x).reduce(math.max),
      top = (region.polygon[0].y + region.polygon[1].y) / 2,
      bottom = (region.polygon[2].y + region.polygon[3].y) / 2,
      height = _lineHeight(region.polygon);

  final double left;
  final double right;
  final double top;
  final double bottom;
  final double height;

  double verticalGapTo(_LineMetrics next) => math.max(0, next.top - bottom);

  double horizontalOverlapRatio(_LineMetrics next) {
    final overlap = math.min(right, next.right) - math.max(left, next.left);
    if (overlap <= 0) {
      return 0;
    }
    final smallerWidth = math.min(right - left, next.right - next.left);
    return smallerWidth <= 0 ? 0 : overlap / smallerWidth;
  }
}

double _lineHeight(List<Point> polygon) {
  if (polygon.length < 4) {
    return 0;
  }
  return (_distance(polygon[0], polygon[3]) +
          _distance(polygon[1], polygon[2])) /
      2;
}

double _distance(Point first, Point second) {
  final dx = first.x - second.x;
  final dy = first.y - second.y;
  return math.sqrt(dx * dx + dy * dy);
}
