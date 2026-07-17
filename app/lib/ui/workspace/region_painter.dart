import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ubuntu_live_text/theme/app_theme.dart';

/// Paints one OCR region polygon with its interaction state.
///
/// [polygon] is already in the painter's local coordinates, produced from the
/// same fitted geometry that positions the hit target, so nothing here
/// rescales.
class RegionPainter extends CustomPainter {
  const RegionPainter({
    required this.polygon,
    required this.selected,
    required this.hovered,
    required this.focused,
  });

  final List<Offset> polygon;
  final bool selected;
  final bool hovered;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    if (polygon.length < 2) {
      return;
    }
    final path = Path()..addPolygon(polygon, true);

    if (selected) {
      canvas.drawPath(
        path,
        Paint()..color = AppColors.ubuntuOrange.withValues(alpha: 0.24),
      );
    } else if (hovered) {
      canvas.drawPath(
        path,
        Paint()..color = Colors.white.withValues(alpha: 0.14),
      );
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = selected ? 2 : 1
      ..color = selected
          ? AppColors.ubuntuOrange
          : Colors.white.withValues(alpha: hovered ? 0.95 : 0.55);
    canvas.drawPath(path, stroke);

    if (focused) {
      final ring = _bounds(polygon).inflate(3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(ring, const Radius.circular(3)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
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
      old.hovered != hovered ||
      old.focused != focused ||
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
