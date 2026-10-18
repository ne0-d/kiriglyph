import 'dart:math' as math;

import 'package:flutter/foundation.dart';

const double rectangleKeyboardDefaultStep = 10;
const double rectangleKeyboardFineStep = 1;
const double rectangleMinimumExtent = 1;

enum SelectionTool { rectangle, freeDraw, twoClicks }

/// Radius of the marker drawn at the first corner in two-click mode.
const double twoClickCornerMarkerRadius = 6;

/// Click opposite corners instead of dragging (WCAG 2.5.7).
@immutable
class TwoClickRectangleSession {
  const TwoClickRectangleSession({this.firstCorner});

  final SelectionPoint? firstCorner;

  bool get awaitingSecondClick => firstCorner != null;

  TwoClickRectangleSession reset() => const TwoClickRectangleSession();

  RectangleSelection? preview(SelectionPoint pointer) {
    final corner = firstCorner;
    if (corner == null) {
      return null;
    }
    return RectangleSelection.fromDrag(corner, pointer);
  }

  ({TwoClickRectangleSession session, RectangleSelection? selection})
  applyClick(SelectionPoint point) {
    final corner = firstCorner;
    if (corner == null) {
      return (
        session: TwoClickRectangleSession(firstCorner: point),
        selection: null,
      );
    }
    return (
      session: const TwoClickRectangleSession(),
      selection: RectangleSelection.fromDrag(corner, point),
    );
  }
}

class SelectionPoint {
  const SelectionPoint(this.x, this.y);

  final double x;
  final double y;
}

class SelectionRect {
  const SelectionRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  bool get isUsable =>
      width >= rectangleMinimumExtent && height >= rectangleMinimumExtent;

  SelectionRect normalized() => SelectionRect(
    left: math.min(left, right),
    top: math.min(top, bottom),
    right: math.max(left, right),
    bottom: math.max(top, bottom),
  );

  SelectionRect clamp(SelectionRect bounds) => SelectionRect(
    left: left.clamp(bounds.left, bounds.right).toDouble(),
    top: top.clamp(bounds.top, bounds.bottom).toDouble(),
    right: right.clamp(bounds.left, bounds.right).toDouble(),
    bottom: bottom.clamp(bounds.top, bounds.bottom).toDouble(),
  ).normalized();

  @override
  bool operator ==(Object other) =>
      other is SelectionRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

enum RectangleKeyboardCommand { arrowLeft, arrowRight, arrowUp, arrowDown }

class RectangleKeyboardModifiers {
  const RectangleKeyboardModifiers({
    this.alt = false,
    this.control = false,
    this.shift = false,
  });

  final bool alt;
  final bool control;
  final bool shift;
}

class RectangleSelection {
  const RectangleSelection(this.rect);

  factory RectangleSelection.fromDrag(
    SelectionPoint start,
    SelectionPoint end,
  ) {
    return RectangleSelection(
      SelectionRect(
        left: start.x,
        top: start.y,
        right: end.x,
        bottom: end.y,
      ).normalized(),
    );
  }

  final SelectionRect rect;

  RectangleSelection reset(SelectionRect bounds) => RectangleSelection(bounds);

  RectangleSelection applyKeyboard(
    RectangleKeyboardCommand command, {
    RectangleKeyboardModifiers modifiers = const RectangleKeyboardModifiers(),
    SelectionRect? bounds,
  }) {
    final step = modifiers.control
        ? rectangleKeyboardFineStep
        : rectangleKeyboardDefaultStep;
    final snapBounds = modifiers.shift ? bounds : null;
    var next = rect;
    if (modifiers.alt) {
      next = switch (command) {
        RectangleKeyboardCommand.arrowLeft => _translate(-step, 0),
        RectangleKeyboardCommand.arrowRight => _translate(step, 0),
        RectangleKeyboardCommand.arrowUp => _translate(0, -step),
        RectangleKeyboardCommand.arrowDown => _translate(0, step),
      };
    } else {
      next = switch (command) {
        RectangleKeyboardCommand.arrowLeft => SelectionRect(
          left: snapBounds?.left ?? rect.left,
          top: rect.top,
          right: math.max(
            rect.left + rectangleMinimumExtent,
            rect.right - step,
          ),
          bottom: rect.bottom,
        ),
        RectangleKeyboardCommand.arrowRight => SelectionRect(
          left: rect.left,
          top: rect.top,
          right: snapBounds?.right ?? rect.right + step,
          bottom: rect.bottom,
        ),
        RectangleKeyboardCommand.arrowUp => SelectionRect(
          left: rect.left,
          top: snapBounds?.top ?? rect.top,
          right: rect.right,
          bottom: math.max(
            rect.top + rectangleMinimumExtent,
            rect.bottom - step,
          ),
        ),
        RectangleKeyboardCommand.arrowDown => SelectionRect(
          left: rect.left,
          top: rect.top,
          right: rect.right,
          bottom: snapBounds?.bottom ?? rect.bottom + step,
        ),
      };
    }
    return RectangleSelection(bounds == null ? next : next.clamp(bounds));
  }

  SelectionRect _translate(double dx, double dy) => SelectionRect(
    left: rect.left + dx,
    top: rect.top + dy,
    right: rect.right + dx,
    bottom: rect.bottom + dy,
  );
}
