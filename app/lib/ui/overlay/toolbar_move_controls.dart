import 'package:flutter/widgets.dart';

/// The toolbar's options menu, handed to the toolbar so it sits inside it.
/// Dragging needs no control: the whole toolbar is the handle.
class ToolbarMoveControls extends InheritedWidget {
  const ToolbarMoveControls({
    super.key,
    required this.menu,
    required super.child,
  });

  final Widget menu;

  static ToolbarMoveControls? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ToolbarMoveControls>();

  @override
  bool updateShouldNotify(ToolbarMoveControls oldWidget) =>
      menu != oldWidget.menu;
}
