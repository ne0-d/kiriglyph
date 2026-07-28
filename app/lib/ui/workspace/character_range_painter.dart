import 'package:flutter/material.dart';

import 'package:ubuntu_live_text/theme/app_theme.dart';

class CharacterRangePainter extends CustomPainter {
  const CharacterRangePainter({
    required this.polygons,
    required this.selected,
    required this.hovered,
  });

  final List<List<Offset>> polygons;
  final List<bool> selected;
  final bool hovered;

  @override
  void paint(Canvas canvas, Size size) {
    for (var index = 0; index < polygons.length; index++) {
      final polygon = polygons[index];
      if (polygon.length < 3 || (!selected[index] && !hovered)) {
        continue;
      }
      final path = Path()..addPolygon(polygon, true);
      canvas.drawPath(
        path,
        Paint()
          ..color = selected[index]
              ? AppColors.ubuntuOrange.withValues(alpha: 0.30)
              : Colors.white.withValues(alpha: 0.10),
      );
      if (selected[index]) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.25
            ..color = AppColors.ubuntuOrange,
        );
      }
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
      oldDelegate.hovered != hovered ||
      !_sameSelected(oldDelegate.selected, selected) ||
      !_samePolygons(oldDelegate.polygons, polygons);

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
}
