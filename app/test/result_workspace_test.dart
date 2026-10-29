import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/selection/region_selection_provider.dart';

import 'support/workspace_harness.dart';

Finder _region(String id) => find.byKey(Key('ocr-region-$id'));

bool _isSelected(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).flagsCollection.isSelected == Tristate.isTrue;

List<String> _selectedRegions(WidgetTester tester) => [
  for (final id in const ['l1', 'l2', 'l3'])
    if (_isSelected(tester, _region(id))) id,
];

/// Pointer position, in canvas coordinates, of a point given as a fraction of
/// the displayed image. Derived from the rendered image rectangle rather than
/// from app code, so it independently checks alignment.
Offset _imagePoint(WidgetTester tester, double fx, double fy) {
  final frame = find.byKey(const Key('overlay-frame'));
  final image = find.byKey(const Key('capture-image'));
  final rect = tester.any(frame)
      ? tester.getRect(frame)
      : tester.getRect(image);
  return Offset(rect.left + rect.width * fx, rect.top + rect.height * fy);
}

Future<void> _tapRegion(WidgetTester tester, String id) async {
  await tester.tap(_region(id));
  await tester.pump();
}

Future<void> _shiftTapRegion(WidgetTester tester, String id) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.tap(_region(id));
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

Future<void> _drawStroke(
  WidgetTester tester,
  List<Offset> points, {
  Duration step = const Duration(milliseconds: 16),
}) async {
  final gesture = await tester.createGesture();
  await gesture.down(points.first);
  await tester.pump(step);
  for (final point in points.skip(1)) {
    await gesture.moveTo(point);
    await tester.pump(step);
  }
  await gesture.up();
  await tester.pump();
}

Future<String?> _clipboardText() async =>
    (await Clipboard.getData(Clipboard.kTextPlain))?.text;

String _selectedText(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byKey(const Key('capture-canvas-focus'))),
).read(regionSelectionProvider).selectedText;

Future<void> _openSample(
  WidgetTester tester,
  Directory testRoot, {
  Size size = const Size(1280, 800),
}) async {
  await openOverlayCanvas(
    tester,
    testRoot: testRoot,
    worker: FakeWorker([sampleResult()]),
    size: size,
  );
}

OcrResult _paragraphClickResult() => resultWith([
  box(
    'p1a',
    'abcd',
    0,
    20,
    10,
    100,
    30,
    ranges: [
      for (var index = 0; index < 4; index++)
        character(
          index,
          'abcd'[index],
          20 + index * 20,
          10,
          40 + index * 20,
          30,
        ),
    ],
  ),
  box(
    'p1b',
    'efgh',
    1,
    20,
    35,
    100,
    55,
    ranges: [
      for (var index = 0; index < 4; index++)
        character(
          index,
          'efgh'[index],
          20 + index * 20,
          35,
          40 + index * 20,
          55,
        ),
    ],
  ),
  box(
    'p2a',
    'wxyz',
    2,
    20,
    80,
    100,
    100,
    ranges: [
      for (var index = 0; index < 4; index++)
        character(
          index,
          'wxyz'[index],
          20 + index * 20,
          80,
          40 + index * 20,
          100,
        ),
    ],
  ),
]);

void main() {
  String? clipboardText;
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('result-workspace-');
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboardText = (call.arguments as Map)['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return <String, dynamic>{'text': clipboardText};
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    root.deleteSync(recursive: true);
  });

  group('region geometry', () {
    testWidgets(
      'the image keeps its aspect ratio and stays inside the canvas',
      (tester) async {
        await _openSample(tester, root);

        final image = tester.getRect(find.byKey(const Key('overlay-frame')));
        expect(
          image.width / image.height,
          closeTo(kImageWidth / kImageHeight, 0.01),
        );
        expect(image.topLeft.dx, greaterThanOrEqualTo(0));
        expect(image.topLeft.dy, greaterThanOrEqualTo(0));
      },
    );

    for (final size in const [Size(1280, 800), Size(800, 600)]) {
      testWidgets('regions line up with the image at ${size.width.toInt()}x'
          '${size.height.toInt()}', (tester) async {
        await _openSample(tester, root, size: size);

        final image = tester.getRect(find.byKey(const Key('overlay-frame')));
        // l1 covers x 20..180 and y 10..25 of the 200 x 100 source image.
        final rect = tester.getRect(_region('l1'));
        expect(rect.left, closeTo(image.left + image.width * 0.10, 0.5));
        expect(rect.right, closeTo(image.left + image.width * 0.90, 0.5));
        expect(rect.center.dy, closeTo(image.top + image.height * 0.175, 0.5));
      });
    }

    testWidgets('alignment follows the image when the window is resized', (
      tester,
    ) async {
      await _openSample(tester, root, size: const Size(1280, 800));
      tester.view.physicalSize = const Size(900, 650);
      await tester.pump();

      final image = tester.getRect(find.byKey(const Key('overlay-frame')));
      final rect = tester.getRect(_region('l1'));
      expect(rect.left, closeTo(image.left + image.width * 0.10, 0.5));

      // And the pointer still lands on the resized region.
      await tester.tapAt(_imagePoint(tester, 0.5, 0.175));
      await tester.pump();
      expect(_selectedRegions(tester), ['l1']);
    });

    testWidgets('tapping where a region is drawn selects it', (tester) async {
      await _openSample(tester, root);

      // Centre of l2: x 20..120 -> 0.35, y 40..55 -> 0.475.
      await tester.tapAt(_imagePoint(tester, 0.35, 0.475));
      await tester.pump();

      expect(_selectedRegions(tester), ['l2']);
    });

    testWidgets('a tiny region can be hit slightly outside its drawn box', (
      tester,
    ) async {
      final worker = FakeWorker([
        resultWith([
          ...sampleResult().regions,
          box('speck', 'Speck', 3, 150, 80, 152, 82),
        ]),
      ]);
      await openOverlayCanvas(tester, testRoot: root, worker: worker);

      final image = tester.getRect(find.byKey(const Key('overlay-frame')));
      final centre = Offset(
        image.left + image.width * (151 / kImageWidth),
        image.top + image.height * (81 / kImageHeight),
      );
      // The drawn box is only a few pixels wide; 10 px away must still hit.
      await tester.tapAt(centre + const Offset(10, 8));
      await tester.pump();

      expect(_isSelected(tester, _region('speck')), isTrue);
    });
  });

  group('selection by pointer', () {
    testWidgets('clicking a character selects and copies only that character', (
      tester,
    ) async {
      await openOverlayCanvas(
        tester,
        testRoot: root,
        worker: FakeWorker([characterSampleResult()]),
      );

      await tester.tapAt(_imagePoint(tester, 0.25, 0.20));
      await tester.pump();
      await tester.tap(find.byKey(const Key('overlay-copy')));
      await tester.pump();

      expect(await _clipboardText(), 'b');
      expect(find.byKey(const Key('ocr-character-line-l1')), findsOneWidget);
    });

    testWidgets(
      'single, double, and triple click select character, word, paragraph',
      (tester) async {
        await openOverlayCanvas(
          tester,
          testRoot: root,
          worker: FakeWorker([wordCharacterResult()]),
        );
        final point = _imagePoint(tester, 0.475, 0.20);

        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 50));
        expect(_selectedText(tester), 't');

        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 50));
        expect(_selectedText(tester), 'two');

        await tester.tapAt(point);
        await tester.pump();
        expect(_selectedText(tester), 'one,,  two!');
      },
    );

    testWidgets('triple-click selects a multi-line paragraph', (tester) async {
      await openOverlayCanvas(
        tester,
        testRoot: root,
        worker: FakeWorker([_paragraphClickResult()]),
      );

      final point = _imagePoint(tester, 0.25, 0.45);
      for (var click = 0; click < 3; click++) {
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(_selectedText(tester), 'abcd\nefgh');
    });

    testWidgets('triple-click selects a one-line paragraph', (tester) async {
      await openOverlayCanvas(
        tester,
        testRoot: root,
        worker: FakeWorker([_paragraphClickResult()]),
      );

      final point = _imagePoint(tester, 0.25, 0.90);
      for (var click = 0; click < 3; click++) {
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(_selectedText(tester), 'wxyz');
    });

    testWidgets('triple-click keeps adjacent paragraphs separate', (
      tester,
    ) async {
      await openOverlayCanvas(
        tester,
        testRoot: root,
        worker: FakeWorker([_paragraphClickResult()]),
      );

      final point = _imagePoint(tester, 0.25, 0.20);
      for (var click = 0; click < 3; click++) {
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(_selectedText(tester), 'abcd\nefgh');
      expect(_selectedText(tester), isNot(contains('wxyz')));
    });

    testWidgets('empty space inside a line box clears character selection', (
      tester,
    ) async {
      await openOverlayCanvas(
        tester,
        testRoot: root,
        worker: FakeWorker([sparseCharacterResult()]),
      );
      await tester.tapAt(_imagePoint(tester, 0.15, 0.20));
      await tester.pump();

      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('overlay-copy')))
            .onPressed,
        isNotNull,
      );

      await tester.tapAt(_imagePoint(tester, 0.30, 0.20));
      await tester.pump();

      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('overlay-copy')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('dragging across characters copies the exact partial range', (
      tester,
    ) async {
      await openOverlayCanvas(
        tester,
        testRoot: root,
        worker: FakeWorker([characterSampleResult()]),
      );

      final start = _imagePoint(tester, 0.225, 0.20);
      final end = _imagePoint(tester, 0.475, 0.20);
      await tester.dragFrom(start, end - start);
      await tester.pump();
      await tester.tap(find.byKey(const Key('overlay-copy')));
      await tester.pump();

      expect(await _clipboardText(), 'bcd');
    });

    testWidgets('dragging off text circles and copies enclosed characters', (
      tester,
    ) async {
      await openOverlayCanvas(
        tester,
        testRoot: root,
        worker: FakeWorker([characterSampleResult()]),
      );
      await tester.tap(find.byTooltip('Free draw'));
      await tester.pump();

      await _drawStroke(tester, [
        _imagePoint(tester, 0.175, 0.05),
        _imagePoint(tester, 0.425, 0.05),
        _imagePoint(tester, 0.425, 0.35),
        _imagePoint(tester, 0.175, 0.35),
        _imagePoint(tester, 0.175, 0.05),
      ]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(await _clipboardText(), 'abcd');
    });

    testWidgets('freehand stroke fades after release', (tester) async {
      await openOverlayCanvas(
        tester,
        testRoot: root,
        worker: FakeWorker([characterSampleResult()]),
      );
      await tester.tap(find.byTooltip('Free draw'));
      await tester.pump();
      final points = [
        _imagePoint(tester, 0.175, 0.05),
        _imagePoint(tester, 0.425, 0.05),
        _imagePoint(tester, 0.425, 0.35),
        _imagePoint(tester, 0.175, 0.35),
        _imagePoint(tester, 0.175, 0.05),
      ];
      final gesture = await tester.createGesture();
      await gesture.down(points.first);
      await tester.pump();
      await gesture.moveTo(points[1]);
      await tester.pump();
      expect(
        find.byKey(const Key('freehand-selection-stroke')),
        findsOneWidget,
      );

      for (final point in points.skip(2)) {
        await gesture.moveTo(point);
        await tester.pump();
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 299));
      expect(
        find.byKey(const Key('freehand-selection-stroke')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 51));
      await tester.pump();
      expect(find.byKey(const Key('freehand-selection-stroke')), findsNothing);
    });

    testWidgets('reduced motion clears freehand stroke immediately', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await openOverlayCanvas(
        tester,
        testRoot: root,
        worker: FakeWorker([characterSampleResult()]),
      );
      await tester.tap(find.byTooltip('Free draw'));
      await tester.pump();

      await _drawStroke(tester, [
        _imagePoint(tester, 0.175, 0.05),
        _imagePoint(tester, 0.425, 0.05),
        _imagePoint(tester, 0.425, 0.35),
        _imagePoint(tester, 0.175, 0.35),
        _imagePoint(tester, 0.175, 0.05),
      ]);

      expect(find.byKey(const Key('freehand-selection-stroke')), findsNothing);
    });

    testWidgets('backward dragging spans lines in reading order', (
      tester,
    ) async {
      await openOverlayCanvas(
        tester,
        testRoot: root,
        worker: FakeWorker([multilineCharacterResult()]),
      );

      final start = _imagePoint(tester, 0.275, 0.50);
      final end = _imagePoint(tester, 0.125, 0.20);
      await tester.dragFrom(start, end - start);
      await tester.pump();
      await tester.tap(find.byKey(const Key('overlay-copy')));
      await tester.pump();

      expect(await _clipboardText(), 'ab\ncd');
    });

    testWidgets('arrow keys replace and extend the character selection', (
      tester,
    ) async {
      await openOverlayCanvas(
        tester,
        testRoot: root,
        worker: FakeWorker([characterSampleResult()]),
      );
      await tester.tapAt(_imagePoint(tester, 0.25, 0.20));
      await tester.pump();

      final canvasFocus = tester
          .widget<Focus>(find.byKey(const Key('capture-canvas-focus')))
          .focusNode!;
      expect(canvasFocus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(await _clipboardText(), 'cd');
      expect(find.text('Copied 1 line'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Ctrl+A then Ctrl+C copies all recognized text', (
      tester,
    ) async {
      await openOverlayCanvas(
        tester,
        testRoot: root,
        worker: FakeWorker([characterSampleResult()]),
      );
      await tester.tapAt(_imagePoint(tester, 0.25, 0.20));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(await _clipboardText(), 'abcd');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('character lines expose text-selection semantics', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await openOverlayCanvas(
        tester,
        testRoot: root,
        worker: FakeWorker([characterSampleResult()]),
      );

      final node = tester.getSemantics(
        find.byKey(const Key('ocr-character-line-l1')),
      );
      expect(node.label, 'Line 1: abcd');
      expect(node.flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });

  group('copying', () {
    testWidgets('Copy selection is enabled only while lines are selected', (
      tester,
    ) async {
      await _openSample(tester, root);

      bool enabled(String key) =>
          tester.widget<IconButton>(find.byKey(Key(key))).onPressed != null;

      expect(enabled('overlay-copy'), isFalse);
      expect(enabled('overlay-copy-all'), isTrue);

      await _tapRegion(tester, 'l1');
      await tester.pump();
      expect(enabled('overlay-copy'), isTrue);

      await tester.tapAt(
        tester.getRect(find.byKey(const Key('capture-canvas'))).topLeft +
            const Offset(4, 4),
      );
      await tester.pump();
      expect(enabled('overlay-copy'), isFalse);
      expect(enabled('overlay-copy-all'), isTrue);
    });

    testWidgets('Copy selection copies only selected lines in reading order', (
      tester,
    ) async {
      await _openSample(tester, root);
      await _tapRegion(tester, 'l3');
      await _shiftTapRegion(tester, 'l2');

      await tester.tap(find.byKey(const Key('overlay-copy')));
      await tester.pump();

      expect(await _clipboardText(), 'Beta line\n\nGamma line');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Copy selection separates selected paragraphs', (tester) async {
      await openOverlayCanvas(
        tester,
        testRoot: root,
        worker: FakeWorker([_paragraphClickResult()]),
      );
      await tester.tapAt(_imagePoint(tester, 0.25, 0.20));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(await _clipboardText(), 'abcd\nefgh\n\nwxyz');
    });

    testWidgets('Copy all copies every line in reading order', (tester) async {
      await _openSample(tester, root);

      await tester.tap(find.byKey(const Key('overlay-copy-all')));
      await tester.pump();

      expect(await _clipboardText(), 'Alpha line\nBeta line\nGamma line');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('copying shows short feedback that then disappears, as a live '
        'region where announcing is unsupported', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final handle = tester.ensureSemantics();
      await _openSample(tester, root);
      await _tapRegion(tester, 'l1');
      await _shiftTapRegion(tester, 'l2');

      await tester.tap(find.byKey(const Key('overlay-copy')));
      await tester.pump();
      expect(find.text('Copied 2 lines'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.text('Copied 2 lines'))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );

      await tester.tap(find.byKey(const Key('overlay-copy-all')));
      await tester.pump();
      expect(find.text('Copied all 3 lines'), findsOneWidget);
      expect(find.text('Copied 2 lines'), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Copied all 3 lines'), findsNothing);
      handle.dispose();
    });

    testWidgets('a single line is described in the singular', (tester) async {
      await _openSample(tester, root);
      await _tapRegion(tester, 'l1');
      await tester.tap(find.byKey(const Key('overlay-copy')));
      await tester.pump();

      expect(find.text('Copied 1 line'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a clipboard failure is reported, not hidden', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'unavailable');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _openSample(tester, root);

      await tester.tap(find.byKey(const Key('overlay-copy-all')));
      await tester.pump();

      expect(find.text('Could not copy. Try again.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
