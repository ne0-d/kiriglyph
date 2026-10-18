import 'dart:math' as math;

import 'package:kiriglyph/ocr/ocr_result.dart';

/// A place on the capture where the O key can put the object cursor.
class ObjectCandidate {
  const ObjectCandidate({required this.point, required this.where});

  /// Source-pixel position; Enter segments the object under it.
  final Point point;

  /// Plain-language location, for example `near top left`.
  final String where;
}

/// Share of a grid cell that recognized text may cover before the cell is
/// left out: those cells are for text selection, not objects.
const objectCandidateTextCoverageLimit = 0.6;

/// Candidate places for keyboard object selection.
///
/// There is no object proposal source yet, so the capture is split into a
/// 3 by 3 grid of areas, ordered top to bottom then left to right, and the
/// areas mostly covered by text are skipped. Each candidate is the centre of
/// its area; the arrow keys fine-tune it before Enter. A future proposal
/// source only has to replace this function.
List<ObjectCandidate> objectCandidates({
  required int imageWidth,
  required int imageHeight,
  required List<TextRegion> regions,
}) {
  if (imageWidth <= 0 || imageHeight <= 0) {
    return const [];
  }
  const rows = ['top', 'middle', 'bottom'];
  const columns = ['left', 'center', 'right'];
  final cellWidth = imageWidth / 3;
  final cellHeight = imageHeight / 3;
  final bounds = [for (final region in regions) _bounds(region)];
  final all = <ObjectCandidate>[];
  final open = <ObjectCandidate>[];
  for (var row = 0; row < 3; row++) {
    for (var column = 0; column < 3; column++) {
      final left = column * cellWidth;
      final top = row * cellHeight;
      final candidate = ObjectCandidate(
        point: Point(x: left + cellWidth / 2, y: top + cellHeight / 2),
        where: _where(rows[row], columns[column]),
      );
      all.add(candidate);
      final covered = _coverage(
        left,
        top,
        left + cellWidth,
        top + cellHeight,
        bounds,
      );
      if (covered <= objectCandidateTextCoverageLimit) {
        open.add(candidate);
      }
    }
  }
  return open.isEmpty ? all : open;
}

/// "Object 2 of 5, near top left".
String objectCandidateAnnouncement(
  int index,
  List<ObjectCandidate> candidates,
) => 'Object ${index + 1} of ${candidates.length}, ${candidates[index].where}';

/// Next index when cycling, wrapping at both ends. [current] null starts at
/// the first (forward) or last (backward) candidate.
int cycleObjectIndex(int? current, int count, {required bool forward}) {
  if (count <= 0) {
    return 0;
  }
  if (current == null) {
    return forward ? 0 : count - 1;
  }
  return (current + (forward ? 1 : -1)) % count;
}

String _where(String row, String column) {
  if (row == 'middle' && column == 'center') {
    return 'near center';
  }
  if (row == 'middle') {
    return 'near $column';
  }
  if (column == 'center') {
    return 'near $row';
  }
  return 'near $row $column';
}

({double left, double top, double right, double bottom}) _bounds(
  TextRegion region,
) {
  var left = double.infinity;
  var top = double.infinity;
  var right = -double.infinity;
  var bottom = -double.infinity;
  for (final point in region.polygon) {
    left = math.min(left, point.x);
    top = math.min(top, point.y);
    right = math.max(right, point.x);
    bottom = math.max(bottom, point.y);
  }
  return (left: left, top: top, right: right, bottom: bottom);
}

double _coverage(
  double left,
  double top,
  double right,
  double bottom,
  List<({double left, double top, double right, double bottom})> boxes,
) {
  final area = (right - left) * (bottom - top);
  if (area <= 0) {
    return 1;
  }
  var covered = 0.0;
  for (final box in boxes) {
    final width = math.min(right, box.right) - math.max(left, box.left);
    final height = math.min(bottom, box.bottom) - math.max(top, box.top);
    if (width > 0 && height > 0) {
      covered += width * height;
    }
  }
  return covered / area;
}
