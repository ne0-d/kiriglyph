import 'dart:ui';

/// A light line with a dark rim stays visible on any pixels, so a selection
/// outline never relies on colour alone (WCAG 1.4.1, 1.4.11).
const dualStrokeLight = Color(0xFFFFFFFF);
const dualStrokeDark = Color(0xFF000000);

/// Extra width of the dark rim, split over both sides of the light core.
const dualStrokeRim = 2.0;

void drawDualStrokePath(Canvas canvas, Path path, {double width = 2}) {
  canvas
    ..drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + dualStrokeRim
        ..color = dualStrokeDark,
    )
    ..drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = dualStrokeLight,
    );
}

void drawDualStrokeRect(Canvas canvas, Rect rect, {double width = 2}) =>
    drawDualStrokePath(canvas, Path()..addRect(rect), width: width);

void drawDualStrokeLine(
  Canvas canvas,
  Offset from,
  Offset to, {
  double width = 2,
}) => drawDualStrokePath(
  canvas,
  Path()
    ..moveTo(from.dx, from.dy)
    ..lineTo(to.dx, to.dy),
  width: width,
);

void drawDualStrokeCircle(
  Canvas canvas,
  Offset center,
  double radius, {
  double width = 2,
}) => drawDualStrokePath(
  canvas,
  Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
  width: width,
);

/// A saturated outline with a thin dark rim and a soft halo: the rectangle
/// boundary stays visible on any pixels without the white and theme-purple
/// of the dual stroke.
void drawNeonOutlineRect(
  Canvas canvas,
  Rect rect, {
  Color color = const Color(0xFFFF2BD6),
  double width = 2,
}) {
  final path = Path()..addRect(rect);
  canvas
    ..drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + 6
        ..color = color.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    )
    ..drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + dualStrokeRim
        ..color = dualStrokeDark.withValues(alpha: 0.6),
    )
    ..drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
}
