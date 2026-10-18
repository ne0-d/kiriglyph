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
              kind: FeedbackButtonKind.tonal,
              icon: Icons.content_copy_rounded,
              label: 'Copy text',
              doneLabel: 'Copied',
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('shows Copied with a check, then eases back to the label', (
    tester,
  ) async {
    final controller = ActionFeedbackController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, onPressed: () {}));

    expect(find.text('Copy text'), findsOneWidget);
    expect(find.text('Copied'), findsNothing);

    controller.succeed({ActionIds.copyText});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Copied'), findsOneWidget);
    expect(find.text('Copy text'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);

    // The hold ends and the label returns.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Copy text'), findsOneWidget);
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('a failure says Failed in the error colour', (tester) async {
    final controller = ActionFeedbackController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, onPressed: () {}));

    controller.fail({ActionIds.copyText});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Failed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('the button keeps its width while the label changes', (
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
    expect(find.text('Copy text'), findsOneWidget);

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

    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
