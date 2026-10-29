import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/ui/overlay/action_feedback.dart';

Widget _host(ActionFeedbackController controller, {VoidCallback? onPressed}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ActionFeedbackScope(
            controller: controller,
            child: FeedbackActionButton(
              buttonKey: const Key('button'),
              actionId: ActionIds.copyText,
              icon: Icons.content_copy_rounded,
              tooltip: 'Copy text',
              doneTooltip: 'Copied',
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('draws a check and says Copied, then eases back', (tester) async {
    final controller = ActionFeedbackController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, onPressed: () {}));

    expect(find.byTooltip('Copy text'), findsOneWidget);
    expect(find.byTooltip('Copied'), findsNothing);

    controller.succeed({ActionIds.copyText});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byTooltip('Copied'), findsOneWidget);
    expect(find.byTooltip('Copy text'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);

    // The hold ends and the idle state returns.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Copy text'), findsOneWidget);
    expect(find.byTooltip('Copied'), findsNothing);
  });

  testWidgets('a failure says Failed', (tester) async {
    final controller = ActionFeedbackController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, onPressed: () {}));

    controller.fail({ActionIds.copyText});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byTooltip('Failed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('the button keeps its size through the confirm cycle', (
    tester,
  ) async {
    final controller = ActionFeedbackController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, onPressed: () {}));
    final before = tester.getSize(find.byKey(const Key('button')));

    controller.succeed({ActionIds.copyText});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.getSize(find.byKey(const Key('button'))), before);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('other actions do not react, and a click still works', (
    tester,
  ) async {
    final controller = ActionFeedbackController();
    addTearDown(controller.dispose);
    var pressed = 0;
    await tester.pumpWidget(_host(controller, onPressed: () => pressed++));

    controller.succeed({ActionIds.saveScreenshot});
    await tester.pump();
    expect(find.byTooltip('Copy text'), findsOneWidget);

    await tester.tap(find.byKey(const Key('button')));
    expect(pressed, 1);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('reduced motion switches state without animating', (
    tester,
  ) async {
    final controller = ActionFeedbackController(reduceMotion: true);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, onPressed: () {}));

    controller.succeed({ActionIds.copyText});
    await tester.pump();
    await tester.pump();

    expect(find.byTooltip('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
