import 'package:flutter/widgets.dart';

/// The move grip and move menu, handed to [OverlayToolbar] so they sit inside
/// it instead of floating above it.
class ToolbarMoveControls extends InheritedWidget {
  const ToolbarMoveControls({
    super.key,
    required this.grip,
    required this.menu,
    required super.child,
  });

  final Widget grip;
  final Widget menu;

  static ToolbarMoveControls? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ToolbarMoveControls>();

  @override
  bool updateShouldNotify(ToolbarMoveControls oldWidget) =>
      grip != oldWidget.grip || menu != oldWidget.menu;
}
