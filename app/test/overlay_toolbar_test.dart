import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/detection/text_detectors.dart';
import 'package:kiriglyph/selection/rectangle_selection.dart';
import 'package:kiriglyph/ui/overlay/overlay_toolbar.dart';

void main() {
  testWidgets(
    'toolbar exposes rectangle/free draw and full screenshot actions',
    (tester) async {
      SelectionTool? selectedTool;
      var savedFull = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverlayToolbar(
              status: 'Ready',
              onCopy: null,
              onCopyAll: null,
              tool: SelectionTool.rectangle,
              onToolChanged: (tool) => selectedTool = tool,
              onSaveFullScreenshot: () => savedFull = true,
              onClose: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Two clicks'));
      await tester.tap(find.byKey(const Key('overlay-save-full-screenshot')));

      expect(selectedTool, SelectionTool.twoClicks);
      expect(savedFull, isTrue);
    },
  );

  testWidgets('selection action chip shows reachable actions and detections', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionActionChip(
            canCopyText: true,
            canLiftObject: true,
            canCopyScreenshot: true,
            canSaveScreenshot: true,
            canSearchWeb: true,
            detections: const [
              DetectedTextItem(
                kind: DetectedTextKind.link,
                text: 'https://example.com',
                target: 'https://example.com',
              ),
            ],
            onCopyText: () {},
            onLiftObject: () {},
            onCopyScreenshot: () {},
            onSaveScreenshot: () {},
            onSearchWeb: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('selection-copy-text')), findsOneWidget);
    expect(find.byKey(const Key('selection-lift-object')), findsOneWidget);
    expect(find.byKey(const Key('selection-copy-screenshot')), findsOneWidget);
    expect(find.byKey(const Key('selection-save-screenshot')), findsOneWidget);
    expect(find.byKey(const Key('selection-search-web')), findsOneWidget);
    expect(find.byTooltip('Open link'), findsOneWidget);
  });

  testWidgets('selection action chip requires confirmation before opening', (
    tester,
  ) async {
    var requested = false;
    var confirmed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionActionChip(
            canCopyText: false,
            canLiftObject: false,
            canCopyScreenshot: false,
            canSaveScreenshot: false,
            canSearchWeb: false,
            confirmTarget: 'https://code.example',
            detections: const [
              DetectedTextItem(
                kind: DetectedTextKind.code,
                text: 'https://code.example',
                target: 'https://code.example',
              ),
            ],
            onOpenDetection: (_) => requested = true,
            onConfirmOpen: () => confirmed = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Open code content'));
    expect(requested, isTrue);
    expect(confirmed, isFalse);
    expect(find.text('Open https://code.example?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('selection-confirm-open')));
    expect(confirmed, isTrue);
  });

  testWidgets('selection action chip makes disallowed code content copy-only', (
    tester,
  ) async {
    var copied = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionActionChip(
            canCopyText: false,
            canLiftObject: false,
            canCopyScreenshot: false,
            canSaveScreenshot: false,
            canSearchWeb: false,
            detections: const [
              DetectedTextItem(
                kind: DetectedTextKind.code,
                text: 'javascript:alert(1)',
                target: '',
              ),
            ],
            onCopyDetection: (_) => copied = true,
          ),
        ),
      ),
    );

    expect(find.byTooltip('Open code content'), findsNothing);
    await tester.tap(find.byKey(const Key('selection-copy-code')));
    expect(copied, isTrue);
  });
}
