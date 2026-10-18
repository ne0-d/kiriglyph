import 'dart:ui';

import 'package:kiriglyph/overlay/display_layout.dart';

/// Where the user wants the toolbar anchored when not dragging freely.
enum ToolbarAnchorMode { auto, top, bottom, followSelection }

/// Per-display toolbar memory for the resident app session (not persisted yet).
class ToolbarSessionPlacement {
  const ToolbarSessionPlacement({
    this.mode = ToolbarAnchorMode.auto,
    this.manualOffset = Offset.zero,
    this.userMovedManually = false,
  });

  final ToolbarAnchorMode mode;
  final Offset manualOffset;
  final bool userMovedManually;

  ToolbarSessionPlacement copyWith({
    ToolbarAnchorMode? mode,
    Offset? manualOffset,
    bool? userMovedManually,
  }) {
    return ToolbarSessionPlacement(
      mode: mode ?? this.mode,
      manualOffset: manualOffset ?? this.manualOffset,
      userMovedManually: userMovedManually ?? this.userMovedManually,
    );
  }
}

/// Stable key for the display the overlay is covering.
String displayIdentityKey(LogicalMonitor monitor) =>
    '${monitor.x},${monitor.y},${monitor.width}x${monitor.height}@${monitor.scaleFactor}';

/// Fallback when monitor metadata is unavailable (e.g. tests): logical size.
String displayIdentityFromSize(Size screen) =>
    '${screen.width.round()}x${screen.height.round()}';

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

  Offset clamp(Offset offset) => clampToolbarOffset(
    screen: screen,
    toolbar: toolbar,
    offset: offset,
    margin: margin,
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

Offset defaultToolbarOffset({
  required Size screen,
  required Size toolbar,
  required ToolbarAnchorMode mode,
  required List<Rect> obstacles,
  Rect? selectionBounds,
  double margin = 24,
}) {
  return switch (mode) {
    ToolbarAnchorMode.top => clampToolbarOffset(
      screen: screen,
      toolbar: toolbar,
      offset: Offset((screen.width - toolbar.width) / 2, margin),
      margin: margin,
    ),
    ToolbarAnchorMode.bottom => clampToolbarOffset(
      screen: screen,
      toolbar: toolbar,
      offset: Offset(
        (screen.width - toolbar.width) / 2,
        screen.height - toolbar.height - margin,
      ),
      margin: margin,
    ),
    ToolbarAnchorMode.followSelection when selectionBounds != null =>
      _followSelection(
        screen: screen,
        toolbar: toolbar,
        selection: selectionBounds,
        margin: margin,
      ),
    _ => placeOverlayToolbar(
      screen: screen,
      toolbar: toolbar,
      obstacles: obstacles,
      margin: margin,
    ),
  };
}

Offset resolveToolbarPosition({
  required Size screen,
  required Size toolbar,
  required List<Rect> obstacles,
  required ToolbarSessionPlacement session,
  Rect? selectionBounds,
  double margin = 24,
}) {
  final base = defaultToolbarOffset(
    screen: screen,
    toolbar: toolbar,
    mode: session.userMovedManually ? ToolbarAnchorMode.auto : session.mode,
    obstacles: obstacles,
    selectionBounds: selectionBounds,
    margin: margin,
  );
  final resolved = base + session.manualOffset;
  var clamped = clampToolbarOffset(
    screen: screen,
    toolbar: toolbar,
    offset: resolved,
    margin: margin,
  );
  if (!session.userMovedManually && selectionBounds != null) {
    clamped = _avoidSelectionIfPossible(
      screen: screen,
      toolbar: toolbar,
      offset: clamped,
      selection: selectionBounds,
      margin: margin,
    );
  }
  return clamped;
}

Offset clampToolbarOffset({
  required Size screen,
  required Size toolbar,
  required Offset offset,
  double margin = 24,
}) {
  final maxX = (screen.width - toolbar.width).clamp(0.0, double.infinity);
  final maxY = (screen.height - toolbar.height).clamp(0.0, double.infinity);
  final minX = margin.clamp(0.0, maxX).toDouble();
  final minY = margin.clamp(0.0, maxY).toDouble();
  return Offset(
    offset.dx.clamp(minX, maxX.toDouble()),
    offset.dy.clamp(minY, maxY.toDouble()),
  );
}

Offset nudgeToolbar({
  required Offset current,
  required Size screen,
  required Size toolbar,
  required Offset delta,
  double margin = 24,
}) {
  return clampToolbarOffset(
    screen: screen,
    toolbar: toolbar,
    offset: current + delta,
    margin: margin,
  );
}

Offset _followSelection({
  required Size screen,
  required Size toolbar,
  required Rect selection,
  required double margin,
}) {
  const gap = 12.0;
  final below = Offset(
    selection.center.dx - toolbar.width / 2,
    selection.bottom + gap,
  );
  final above = Offset(
    selection.center.dx - toolbar.width / 2,
    selection.top - toolbar.height - gap,
  );
  final belowClamped = clampToolbarOffset(
    screen: screen,
    toolbar: toolbar,
    offset: below,
    margin: margin,
  );
  if ((belowClamped.dy + toolbar.height) <= screen.height - margin) {
    return belowClamped;
  }
  return clampToolbarOffset(
    screen: screen,
    toolbar: toolbar,
    offset: above,
    margin: margin,
  );
}

Offset _avoidSelectionIfPossible({
  required Size screen,
  required Size toolbar,
  required Offset offset,
  required Rect selection,
  required double margin,
}) {
  final rect = offset & toolbar;
  final overlap = rect.intersect(selection);
  if (overlap.width <= 0 || overlap.height <= 0) {
    return offset;
  }
  final candidates = [
    Offset(offset.dx, selection.top - toolbar.height - 12),
    Offset(offset.dx, selection.bottom + 12),
    Offset(selection.right + 12, offset.dy),
    Offset(selection.left - toolbar.width - 12, offset.dy),
  ];
  for (final candidate in candidates) {
    final clamped = clampToolbarOffset(
      screen: screen,
      toolbar: toolbar,
      offset: candidate,
      margin: margin,
    );
    final candidateRect = clamped & toolbar;
    final candidateOverlap = candidateRect.intersect(selection);
    if (candidateOverlap.width <= 0 || candidateOverlap.height <= 0) {
      return clamped;
    }
  }
  return offset;
}
