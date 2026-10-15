import 'package:flutter/material.dart';

import 'package:kiriglyph/ui/workspace/selection_band_geometry.dart';

/// The outline that marks selected text independently of its tint.
Paint selectionOutlinePaint(Color selectionColor) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = 2
  ..strokeJoin = StrokeJoin.round
  ..color = selectionColor.withValues(alpha: 0.95);

class CharacterRangePainter extends CustomPainter {
  const CharacterRangePainter({
    required this.polygons,
    required this.linePolygon,
    required this.selected,
    required this.focused,
    required this.selectionColor,
  });

  final List<List<Offset>> polygons;
  final List<Offset> linePolygon;
  final List<bool> selected;
  final bool focused;
  final Color selectionColor;

  @override
  void paint(Canvas canvas, Size size) {
    final band = buildLineSelectionBand(
      characterPolygons: polygons,
      selected: selected,
      linePolygon: linePolygon,
    );
    if (band != null) {
      final path = Path()..addPolygon(band, true);
      canvas
        ..drawPath(path, Paint()..color = selectionColor)
        // An outline, so selection shows without relying on the tint.
        ..drawPath(path, selectionOutlinePaint(selectionColor));
    }

    if (focused) {
      _paintFocusIndicator(canvas);
    }
  }

  @override
  bool? hitTest(Offset position) => polygons.any(
    (polygon) =>
        polygon.length >= 3 &&
        (Path()..addPolygon(polygon, true)).contains(position),
  );

  @override
  bool shouldRepaint(covariant CharacterRangePainter oldDelegate) =>
      oldDelegate.focused != focused ||
      oldDelegate.selectionColor != selectionColor ||
      !_sameSelected(oldDelegate.selected, selected) ||
      !_samePolygon(oldDelegate.linePolygon, linePolygon) ||
      !_samePolygons(oldDelegate.polygons, polygons);

  void _paintFocusIndicator(Canvas canvas) {
    if (linePolygon.length >= 4) {
      canvas.drawLine(
        linePolygon[3],
        linePolygon[2],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.72),
      );
      return;
    }
    if (polygons.isEmpty) {
      return;
    }
    final bounds = _bounds([
      for (final polygon in polygons)
        for (final point in polygon) point,
    ]);
    canvas.drawLine(
      bounds.bottomLeft,
      bounds.bottomRight,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.72),
    );
  }

  static Rect _bounds(List<Offset> points) {
    var left = points.first.dx;
    var right = left;
    var top = points.first.dy;
    var bottom = top;
    for (final p in points.skip(1)) {
      left = left < p.dx ? left : p.dx;
      right = right > p.dx ? right : p.dx;
      top = top < p.dy ? top : p.dy;
      bottom = bottom > p.dy ? bottom : p.dy;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static bool _sameSelected(List<bool> first, List<bool> second) {
    if (first.length != second.length) {
      return false;
    }
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }
    return true;
  }

  static bool _samePolygons(
    List<List<Offset>> first,
    List<List<Offset>> second,
  ) {
    if (first.length != second.length) {
      return false;
    }
    for (var index = 0; index < first.length; index++) {
      if (first[index].length != second[index].length) {
        return false;
      }
      for (var point = 0; point < first[index].length; point++) {
        if (first[index][point] != second[index][point]) {
          return false;
        }
      }
    }
    return true;
  }

  static bool _samePolygon(List<Offset> first, List<Offset> second) {
    if (first.length != second.length) {
      return false;
    }
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }
    return true;
  }
}
