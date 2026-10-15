import 'dart:ui';

/// Picks where the floating overlay toolbar goes: the first edge position, in
/// order of preference, whose rectangle covers none of [obstacles]. Falls
/// back to the position covering the least obstacle area.
Offset placeOverlayToolbar({
  required Size screen,
  required Size toolbar,
  required List<Rect> obstacles,
  double margin = 24,
}) {
  final left = margin;
  final right = screen.width - toolbar.width - margin;
  final centre = (screen.width - toolbar.width) / 2;
  final top = margin;
  final bottom = screen.height - toolbar.height - margin;
  final candidates = [
    Offset(centre, bottom),
    Offset(centre, top),
    Offset(right, bottom),
    Offset(left, bottom),
    Offset(right, top),
    Offset(left, top),
  ];

  Offset clamp(Offset offset) => Offset(
    offset.dx.clamp(
      0,
      (screen.width - toolbar.width).clamp(0, double.infinity),
    ),
    offset.dy.clamp(
      0,
      (screen.height - toolbar.height).clamp(0, double.infinity),
    ),
  );

  double covered(Offset offset) {
    final rect = offset & toolbar;
    var area = 0.0;
    for (final obstacle in obstacles) {
      final overlap = rect.intersect(obstacle);
      if (overlap.width > 0 && overlap.height > 0) {
        area += overlap.width * overlap.height;
      }
    }
    return area;
  }

  var best = clamp(candidates.first);
  var bestArea = double.infinity;
  for (final candidate in candidates.map(clamp)) {
    final area = covered(candidate);
    if (area == 0) {
      return candidate;
    }
    if (area < bestArea) {
      best = candidate;
      bestArea = area;
    }
  }
  return best;
}
