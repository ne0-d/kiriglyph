import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/overlay/toolbar_placement.dart';
import 'package:kiriglyph/selection/rectangle_selection.dart';
import 'package:kiriglyph/ui/motion/motion_policy.dart';
import 'package:kiriglyph/ui/overlay/overlay_toolbar.dart';
import 'package:kiriglyph/ui/overlay/overlay_toolbar_host.dart';
import 'package:kiriglyph/ui/overlay/toolbar_session.dart';

void main() {
  testWidgets('drag grip moves toolbar within the screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: OverlayToolbarHost(
                displayKey: '800x400',
                screen: const Size(800, 400),
                obstacles: const [],
                selectionBounds: null,
                policy: MotionPolicy.full,
                toolbar: OverlayToolbar(
                  status: 'Ready',
                  onCopy: null,
                  onCopyAll: null,
                  tool: SelectionTool.rectangle,
                  onToolChanged: (_) {},
                  onSaveFullScreenshot: () {},
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final grip = find.byKey(const Key('overlay-toolbar-move-grip'));
    expect(grip, findsOneWidget);
    final before = tester.getTopLeft(find.byKey(const Key('overlay-toolbar')));
    final gesture = await tester.startGesture(tester.getCenter(grip));
    await gesture.moveBy(const Offset(40, -30));
    await tester.pump();
    final after = tester.getTopLeft(find.byKey(const Key('overlay-toolbar')));
    expect(after, isNot(equals(before)));
    await gesture.up();
    await tester.pump();

    // The grip and the move menu sit inside the toolbar, not above it.
    final toolbar = tester.getRect(find.byKey(const Key('overlay-toolbar')));
    expect(toolbar.contains(tester.getCenter(grip)), isTrue);
    expect(
      toolbar.contains(
        tester.getCenter(find.byKey(const Key('overlay-toolbar-move-menu'))),
      ),
      isTrue,
    );

    // Any part of the toolbar drags it, not just the grip.
    final status = find.byKey(const Key('overlay-status'));
    final start = tester.getTopLeft(find.byKey(const Key('overlay-toolbar')));
    final drag = await tester.startGesture(tester.getCenter(status));
    await drag.moveBy(const Offset(-30, 20));
    await drag.up();
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const Key('overlay-toolbar'))),
      isNot(equals(start)),
    );
  });

  testWidgets('Alt+arrow shortcut nudges toolbar session offset', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 800,
                  height: 400,
                  child: OverlayToolbarHost(
                    displayKey: '800x400',
                    screen: const Size(800, 400),
                    obstacles: const [],
                    selectionBounds: null,
                    policy: MotionPolicy.full,
                    toolbar: OverlayToolbar(
                      status: 'Ready',
                      onCopy: null,
                      onCopyAll: null,
                      tool: SelectionTool.rectangle,
                      onToolChanged: (_) {},
                      onSaveFullScreenshot: () {},
                      onClose: () {},
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    Actions.invoke(
      tester.element(find.byKey(const Key('overlay-toolbar-focus'))),
      const NudgeOverlayToolbarIntent(Offset(0, -16)),
    );
    await tester.pump();

    final session = container.read(toolbarSessionProvider)['800x400'];
    expect(session?.userMovedManually, isTrue);
    expect(session?.manualOffset.dy, lessThan(0));
  });

  testWidgets('move menu sets top anchor in session', (tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 800,
                  height: 400,
                  child: OverlayToolbarHost(
                    displayKey: '800x400',
                    screen: const Size(800, 400),
                    obstacles: const [],
                    selectionBounds: null,
                    policy: MotionPolicy.full,
                    toolbar: OverlayToolbar(
                      status: 'Ready',
                      onCopy: null,
                      onCopyAll: null,
                      tool: SelectionTool.rectangle,
                      onToolChanged: (_) {},
                      onSaveFullScreenshot: () {},
                      onClose: () {},
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('overlay-toolbar-move-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top'));
    await tester.pumpAndSettle();

    final session = container.read(toolbarSessionProvider)['800x400'];
    expect(session?.mode, ToolbarAnchorMode.top);
  });
}
