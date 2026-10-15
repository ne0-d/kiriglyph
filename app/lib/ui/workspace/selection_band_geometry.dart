import 'dart:ui';

/// Builds the single document-style highlight band for one OCR text line.
///
/// Character polygons are expected in reading order with points ordered as
/// top-leading, top-trailing, bottom-trailing, bottom-leading. The returned
/// band uses the selected range's leading/trailing edges while taking its
/// vertical extent from the full line polygon.
List<Offset>? buildLineSelectionBand({
  required List<List<Offset>> characterPolygons,
  required List<bool> selected,
  required List<Offset> linePolygon,
}) {
  if (characterPolygons.isEmpty || selected.isEmpty || linePolygon.length < 4) {
    return null;
  }

  int? firstSelected;
  int? lastSelected;
  final count = characterPolygons.length < selected.length
      ? characterPolygons.length
      : selected.length;
  for (var index = 0; index < count; index++) {
    if (selected[index] && characterPolygons[index].length >= 4) {
      firstSelected ??= index;
      lastSelected = index;
    }
  }
  if (firstSelected == null || lastSelected == null) {
    return null;
  }

  final leading = _edgeMidpoint(
    characterPolygons[firstSelected][0],
    characterPolygons[firstSelected][3],
  );
  final trailing = _edgeMidpoint(
    characterPolygons[lastSelected][1],
    characterPolygons[lastSelected][2],
  );

  final lineLeading = _edgeMidpoint(linePolygon[0], linePolygon[3]);
  final lineTrailing = _edgeMidpoint(linePolygon[1], linePolygon[2]);
  final axis = lineTrailing - lineLeading;
  final axisLengthSquared = axis.dx * axis.dx + axis.dy * axis.dy;
  if (axisLengthSquared == 0) {
    return null;
  }

  final leadingT = _projectAmount(
    leading,
    lineLeading,
    axis,
    axisLengthSquared,
  );
  final trailingT = _projectAmount(
    trailing,
    lineLeading,
    axis,
    axisLengthSquared,
  );

  final startT = leadingT.clamp(0.0, 1.0);
  final endT = trailingT.clamp(0.0, 1.0);
  if (startT >= endT) {
    return null;
  }

  return [
    Offset.lerp(linePolygon[0], linePolygon[1], startT)!,
    Offset.lerp(linePolygon[0], linePolygon[1], endT)!,
    Offset.lerp(linePolygon[3], linePolygon[2], endT)!,
    Offset.lerp(linePolygon[3], linePolygon[2], startT)!,
  ];
}

Offset _edgeMidpoint(Offset first, Offset second) =>
    Offset((first.dx + second.dx) / 2, (first.dy + second.dy) / 2);

double _projectAmount(
  Offset point,
  Offset origin,
  Offset axis,
  double axisLengthSquared,
) {
  final relative = point - origin;
  return (relative.dx * axis.dx + relative.dy * axis.dy) / axisLengthSquared;
}
