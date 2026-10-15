import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kiriglyph/ui/workspace/character_range_painter.dart'
    show selectionOutlinePaint;

/// Paints one OCR region polygon with its interaction state.
///
/// [polygon] is already in the painter's local coordinates, produced from the
/// same fitted geometry that positions the hit target, so nothing here
/// rescales.
class RegionPainter extends CustomPainter {
  const RegionPainter({
    required this.polygon,
    required this.selected,
    required this.focused,
    required this.selectionColor,
  });

  final List<Offset> polygon;
  final bool selected;
  final bool focused;
  final Color selectionColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (polygon.length < 2) {
      return;
    }
    final path = Path()..addPolygon(polygon, true);

    if (selected) {
      canvas
        ..drawPath(path, Paint()..color = selectionColor)
        ..drawPath(path, selectionOutlinePaint(selectionColor));
    }

    if (focused) {
      final (start, end) = polygon.length >= 4
          ? (polygon[3], polygon[2])
          : (_bounds(polygon).bottomLeft, _bounds(polygon).bottomRight);
      canvas.drawLine(
        start,
        end,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.72),
      );
    }
  }

  static Rect _bounds(List<Offset> points) {
    var left = points.first.dx;
    var right = left;
    var top = points.first.dy;
    var bottom = top;
    for (final p in points.skip(1)) {
      left = math.min(left, p.dx);
      right = math.max(right, p.dx);
      top = math.min(top, p.dy);
      bottom = math.max(bottom, p.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  bool shouldRepaint(covariant RegionPainter old) =>
      old.selected != selected ||
      old.focused != focused ||
      old.selectionColor != selectionColor ||
      !_samePolygon(old.polygon, polygon);

  static bool _samePolygon(List<Offset> a, List<Offset> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
