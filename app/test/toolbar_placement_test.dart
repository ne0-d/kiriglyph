import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/overlay/display_layout.dart';
import 'package:kiriglyph/overlay/toolbar_placement.dart';

void main() {
  const screen = Size(800, 400);
  const toolbar = Size(320, 48);

  test('displayIdentityKey is stable for a monitor', () {
    const monitor = LogicalMonitor(
      x: 0,
      y: 0,
      width: 1920,
      height: 1080,
      scaleFactor: 2,
    );
    expect(displayIdentityKey(monitor), '0,0,1920x1080@2');
  });

  test('clampToolbarOffset keeps the toolbar inside the safe area', () {
    final clamped = clampToolbarOffset(
      screen: screen,
      toolbar: toolbar,
      offset: const Offset(900, -40),
    );
    expect(clamped.dx, lessThanOrEqualTo(screen.width - toolbar.width));
    expect(clamped.dy, greaterThanOrEqualTo(24));
  });

  test('resolveToolbarPosition avoids selection when not manually moved', () {
    const selection = Rect.fromLTWH(300, 180, 200, 80);
    final offset = resolveToolbarPosition(
      screen: screen,
      toolbar: toolbar,
      obstacles: const [],
      session: const ToolbarSessionPlacement(),
      selectionBounds: selection,
    );
    final toolbarRect = offset & toolbar;
    expect(toolbarRect.overlaps(selection), isFalse);
  });

  test('nudgeToolbar moves by keyboard delta and clamps', () {
    final next = nudgeToolbar(
      current: const Offset(100, 100),
      screen: screen,
      toolbar: toolbar,
      delta: const Offset(1000, 0),
    );
    expect(next.dx, screen.width - toolbar.width);
  });
}
