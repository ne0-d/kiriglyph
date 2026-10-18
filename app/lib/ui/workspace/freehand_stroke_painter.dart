import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/theme/app_theme.dart';
import 'package:kiriglyph/ui/motion/motion_policy.dart';
import 'package:kiriglyph/ui/workspace/fitted_image_geometry.dart';

/// Paints the free-draw trail and optional closed-loop fill preview.
class FreehandStrokePainter extends CustomPainter {
  const FreehandStrokePainter({
    required this.points,
    required this.geometry,
    required this.transform,
    required this.opacity,
    required this.color,
    required this.secondaryColor,
    required this.policy,
    required this.closedLoop,
  });

  final List<Point> points;
  final FittedImageGeometry geometry;
  final Matrix4 transform;
  final double opacity;
  final Color color;
  final Color secondaryColor;
  final MotionPolicy policy;
  final bool closedLoop;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || opacity <= 0) {
      return;
    }
    final viewportPoints = [
      for (final point in points)
        MatrixUtils.transformPoint(transform, geometry.mapPoint(point)),
    ];
    if (policy == MotionPolicy.reduced) {
      _paintReduced(canvas, viewportPoints);
      return;
    }
    _paintFull(canvas, viewportPoints);
  }

  void _paintReduced(Canvas canvas, List<Offset> viewportPoints) {
    final path = Path()
      ..moveTo(viewportPoints.first.dx, viewportPoints.first.dy);
    for (final point in viewportPoints.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    if (closedLoop && viewportPoints.length >= 3) {
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: 0.12),
      );
    }
    // No blur or animation, but still a thick neon line with a dark rim.
    canvas
      ..drawPath(path, _stroke(9, Colors.black.withValues(alpha: 0.45)))
      ..drawPath(path, _stroke(6, color.withValues(alpha: 0.95)))
      ..drawPath(path, _stroke(2, AppColors.neonCore.withValues(alpha: 0.9)));
  }

  static Paint _stroke(double width, Color color) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = color;

  void _paintFull(Canvas canvas, List<Offset> viewportPoints) {
    final smooth = centripetalCatmullRomPath(
      viewportPoints,
      closed: closedLoop,
    );
    if (closedLoop && viewportPoints.length >= 3) {
      canvas.drawPath(
        smooth,
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: 0.08 * opacity),
      );
      _drawDashedPath(
        canvas,
        smooth,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: 0.35 * opacity),
        dashLength: 6,
        gapLength: 4,
      );
    }

    final bounds = _boundsOf(viewportPoints).inflate(16);
    Shader gradient(double alpha) => LinearGradient(
      colors: [
        color.withValues(alpha: alpha * opacity),
        secondaryColor.withValues(alpha: alpha * opacity),
      ],
    ).createShader(bounds);

    // Neon tube: a dark rim for contrast on light screenshots, two blurred
    // glows, a saturated core and a hot white centre.
    canvas
      ..drawPath(
        smooth,
        _stroke(11, Colors.black.withValues(alpha: 0.3 * opacity)),
      )
      ..drawPath(
        smooth,
        _stroke(24, color)
          ..shader = gradient(0.32)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      )
      ..drawPath(
        smooth,
        _stroke(13, color)
          ..shader = gradient(0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      )
      ..drawPath(smooth, _stroke(7, color)..shader = gradient(1))
      ..drawPath(
        smooth,
        _stroke(2.4, AppColors.neonCore.withValues(alpha: 0.95 * opacity)),
      );
  }

  static void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dashLength,
    required double gapLength,
  }) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLength;
      }
    }
  }

  static Rect _boundsOf(List<Offset> points) {
    var left = points.first.dx;
    var top = points.first.dy;
    var right = points.first.dx;
    var bottom = points.first.dy;
    for (final point in points.skip(1)) {
      left = math.min(left, point.dx);
      top = math.min(top, point.dy);
      right = math.max(right, point.dx);
      bottom = math.max(bottom, point.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Centripetal (alpha = 0.5) Catmull-Rom spline through [points].
  static Path centripetalCatmullRomPath(
    List<Offset> points, {
    bool closed = false,
    double alpha = 0.5,
  }) {
    if (points.isEmpty) {
      return Path();
    }
    if (points.length == 1) {
      return Path()..moveTo(points.first.dx, points.first.dy);
    }
    if (points.length == 2) {
      return Path()
        ..moveTo(points[0].dx, points[0].dy)
        ..lineTo(points[1].dx, points[1].dy);
    }

    final extended = <Offset>[...points];
    if (closed) {
      extended
        ..insert(0, points.last)
        ..add(points.first)
        ..add(points[1]);
    } else {
      extended
        ..insert(0, points.first)
        ..add(points.last);
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    final segmentCount = closed ? points.length : points.length - 1;
    for (var index = 0; index < segmentCount; index++) {
      final p0 = extended[index];
      final p1 = extended[index + 1];
      final p2 = extended[index + 2];
      final p3 = extended[index + 3];
      const t0 = 0.0;
      final t1 = _tangent(p0, p1, alpha) + t0;
      final t2 = _tangent(p1, p2, alpha) + t1;
      final t3 = _tangent(p2, p3, alpha) + t2;
      for (var step = 1; step <= 8; step++) {
        final t = t1 + (t2 - t1) * (step / 8);
        final a1 = _lerpOffset(p0, p1, t0, t1, t);
        final a2 = _lerpOffset(p1, p2, t1, t2, t);
        final a3 = _lerpOffset(p2, p3, t2, t3, t);
        final b1 = _lerpOffset(a1, a2, t0, t2, t);
        final b2 = _lerpOffset(a2, a3, t1, t3, t);
        final c = _lerpOffset(b1, b2, t1, t2, t);
        path.lineTo(c.dx, c.dy);
      }
    }
    if (closed) {
      path.close();
    }
    return path;
  }

  static double _tangent(Offset a, Offset b, double alpha) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    return math.pow(dx * dx + dy * dy, alpha / 2).toDouble();
  }

  static Offset _lerpOffset(
    Offset a,
    Offset b,
    double ta,
    double tb,
    double t,
  ) {
    if ((tb - ta).abs() < 1e-6) {
      return a;
    }
    final u = (t - ta) / (tb - ta);
    return Offset.lerp(a, b, u)!;
  }

  @override
  bool shouldRepaint(covariant FreehandStrokePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.geometry != geometry ||
      oldDelegate.transform != transform ||
      oldDelegate.opacity != opacity ||
      oldDelegate.color != color ||
      oldDelegate.secondaryColor != secondaryColor ||
      oldDelegate.policy != policy ||
      oldDelegate.closedLoop != closedLoop;
}
