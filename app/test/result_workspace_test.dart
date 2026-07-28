import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/protocol/protocol_error.dart';
import 'package:ubuntu_live_text/selection/region_selection_provider.dart';
import 'package:ubuntu_live_text/worker/ocr_worker.dart';

import 'support/workspace_harness.dart';

Finder _region(String id) => find.byKey(Key('ocr-region-$id'));
Finder _row(String id) => find.byKey(Key('ocr-row-$id'));

bool _isSelected(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).flagsCollection.isSelected == Tristate.isTrue;

List<String> _selectedRows(WidgetTester tester) => [
  for (final id in const ['l1', 'l2', 'l3'])
    if (_isSelected(tester, _row(id))) id,
];

List<String> _selectedRegions(WidgetTester tester) => [
  for (final id in const ['l1', 'l2', 'l3'])
    if (_isSelected(tester, _region(id))) id,
];

/// Pointer position, in canvas coordinates, of a point given as a fraction of
/// the displayed image. Derived from the rendered image rectangle rather than
/// from app code, so it independently checks alignment.
Offset _imagePoint(WidgetTester tester, double fx, double fy) {
  final image = tester.getRect(find.byKey(const Key('capture-image')));
  return Offset(image.left + image.width * fx, image.top + image.height * fy);
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

Future<String?> _clipboardText() async =>
    (await Clipboard.getData(Clipboard.kTextPlain))?.text;

String _selectedText(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byKey(const Key('capture-canvas-focus'))),
).read(regionSelectionProvider).selectedText;

Future<void> _openSample(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
}) async {
  await pumpApp(tester, worker: FakeWorker([sampleResult()]), size: size);
  await openImage(tester);
}

class _PendingWorker implements OcrWorker {
  final Completer<OcrResult> _result = Completer<OcrResult>();

  @override
  Future<void> cancelActive() async {}

  @override
  Future<OcrResult> recognize(String imagePath) => _result.future;

  void complete(OcrResult result) => _result.complete(result);

  @override
  Future<void> restart() async {}

  @override
  Future<void> close() async {}
}

void main() {
  String? clipboardText;

  setUp(() {
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
  });

  group('workspace presentation', () {
    testWidgets('shows the file name, line count, duration and numbered lines '
        'in reading order', (tester) async {
      await _openSample(tester);

      expect(find.text('receipt.png'), findsOneWidget);
      expect(find.text('3 lines · 420 ms'), findsOneWidget);

      final alpha = tester.getTopLeft(find.text('Alpha line'));
      final beta = tester.getTopLeft(find.text('Beta line'));
      final gamma = tester.getTopLeft(find.text('Gamma line'));
      expect(alpha.dy, lessThan(beta.dy));
      expect(beta.dy, lessThan(gamma.dy));

      for (final (id, number) in const [
        ('l1', '1'),
        ('l2', '2'),
        ('l3', '3'),
      ]) {
        expect(
          find.descendant(of: _row(id), matching: find.text(number)),
          findsOneWidget,
          reason: 'row $id shows reading-order number $number',
        );
      }
    });

    testWidgets('recognized text is ordinary selectable text', (tester) async {
      await _openSample(tester);

      for (final line in const ['Alpha line', 'Beta line', 'Gamma line']) {
        expect(
          find.descendant(
            of: find.byType(SelectionArea),
            matching: find.text(line),
          ),
          findsOneWidget,
          reason: '$line is inside a SelectionArea',
        );
      }
    });

    testWidgets('a result with no lines explains itself and disables copying', (
      tester,
    ) async {
      await pumpApp(tester, worker: FakeWorker([resultWith(const [])]));
      await openImage(tester);

      expect(find.text('No text found'), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('copy-all')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('recognition failure shows the message and allows another '
        'image', (tester) async {
      final worker = FakeWorker([
        WorkerError(code: 'ocr_failed', message: 'Engine exploded.'),
        sampleResult(),
      ]);
      await pumpApp(tester, worker: worker);

      await openImage(tester);
      expect(
        find.text('Text recognition failed. Try another image.'),
        findsOneWidget,
      );
      expect(find.text('Engine exploded.'), findsNothing);
      expect(find.text('Could not recognize text'), findsOneWidget);

      await openImage(tester);
      expect(_region('l1'), findsOneWidget);
    });

    testWidgets('recognizing shows progress and no stale regions', (
      tester,
    ) async {
      final picker = FakePicker();
      final worker = _PendingWorker();
      await pumpApp(tester, picker: picker, worker: worker);

      await tester.tap(find.byKey(const Key('open-image-fab')));
      await tester.pump();

      expect(find.text('Local OCR'), findsOneWidget);
      expect(_region('l1'), findsNothing);

      worker.complete(sampleResult());
      await tester.pump();
    });

    testWidgets('recognition can be cancelled without waiting for the worker', (
      tester,
    ) async {
      await pumpApp(tester, worker: _PendingWorker());

      await tester.tap(find.byKey(const Key('open-image-fab')));
      await tester.pump();
      expect(find.byKey(const Key('cancel-recognition')), findsOneWidget);

      await tester.tap(find.byKey(const Key('cancel-recognition')));
      await tester.pump();

      expect(find.text('Open an image'), findsOneWidget);
      expect(find.text('Local OCR'), findsNothing);
    });

    testWidgets('a failed recognition can retry the same image', (
      tester,
    ) async {
      final picker = FakePicker(path: '/tmp/retry.png');
      final worker = FakeWorker([
        WorkerError(code: 'ocr_failed', message: 'private engine detail'),
        sampleResult(),
      ]);
      await pumpApp(tester, picker: picker, worker: worker);

      await openImage(tester);
      expect(
        find.text('Text recognition failed. Try another image.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('retry-recognition')), findsOneWidget);

      await tester.tap(find.byKey(const Key('retry-recognition')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(_region('l1'), findsOneWidget);
      expect(picker.calls, 1);
      expect(worker.calls, 2);
    });
  });

  group('responsive layout', () {
    for (final (label, size) in const [
      ('wide desktop', Size(1280, 800)),
      ('medium window', Size(900, 600)),
      ('narrow window', Size(800, 600)),
      ('phone-width window', Size(360, 640)),
      ('very short window', Size(640, 300)),
    ]) {
      testWidgets('does not overflow in a $label', (tester) async {
        await _openSample(tester, size: size);

        expect(tester.takeException(), isNull);
        expect(_region('l1'), findsOneWidget);
        expect(find.text('Copy all'), findsOneWidget);

        // Still fine once a selection and feedback are showing.
        await _tapRegion(tester, 'l1');
        await tester.pump();
        await tester.tap(find.byKey(const Key('copy-selection')));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 3));
      });
    }

    testWidgets('places the text panel beside the canvas when wide', (
      tester,
    ) async {
      await _openSample(tester, size: const Size(1280, 800));

      final canvas = tester.getRect(find.byKey(const Key('capture-canvas')));
      final panel = tester.getRect(find.byKey(const Key('text-panel')));
      expect(canvas.right, lessThanOrEqualTo(panel.left));
      expect(canvas.left, lessThan(panel.left));
    });

    testWidgets('stacks the text panel below the canvas when narrow', (
      tester,
    ) async {
      await _openSample(tester, size: const Size(700, 700));

      final canvas = tester.getRect(find.byKey(const Key('capture-canvas')));
      final panel = tester.getRect(find.byKey(const Key('text-panel')));
      expect(canvas.bottom, lessThanOrEqualTo(panel.top));
      expect(panel.width, closeTo(canvas.width, 1));
    });

    testWidgets('recovery controls do not overflow in a compact window', (
      tester,
    ) async {
      await pumpApp(
        tester,
        worker: _PendingWorker(),
        size: const Size(360, 640),
      );
      await tester.tap(find.byKey(const Key('open-image-fab')));
      await tester.pump();
      expect(find.byKey(const Key('cancel-recognition')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('cancel-recognition')));
      await tester.pump();
      await pumpApp(
        tester,
        worker: FakeWorker([
          WorkerError(code: 'ocr_failed', message: 'private detail'),
        ]),
        size: const Size(360, 640),
      );
      await openImage(tester);
      expect(find.byKey(const Key('retry-recognition')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('region geometry', () {
    testWidgets(
      'the image keeps its aspect ratio and stays inside the canvas',
      (tester) async {
        await _openSample(tester);

        final canvas = tester.getRect(find.byKey(const Key('capture-canvas')));
        final image = tester.getRect(find.byKey(const Key('capture-image')));
        expect(
          image.width / image.height,
          closeTo(kImageWidth / kImageHeight, 0.01),
        );
        expect(canvas.contains(image.topLeft), isTrue);
        expect(canvas.contains(image.bottomRight), isTrue);
      },
    );

    for (final size in const [
      Size(1280, 800),
      Size(800, 600),
      Size(480, 700),
    ]) {
      testWidgets('regions line up with the image at ${size.width.toInt()}x'
          '${size.height.toInt()}', (tester) async {
        await _openSample(tester, size: size);

        final image = tester.getRect(find.byKey(const Key('capture-image')));
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
      await _openSample(tester, size: const Size(1280, 800));
      tester.view.physicalSize = const Size(900, 650);
      await tester.pump();

      final image = tester.getRect(find.byKey(const Key('capture-image')));
      final rect = tester.getRect(_region('l1'));
      expect(rect.left, closeTo(image.left + image.width * 0.10, 0.5));

      // And the pointer still lands on the resized region.
      await tester.tapAt(_imagePoint(tester, 0.5, 0.175));
      await tester.pump();
      expect(_selectedRegions(tester), ['l1']);
    });

    testWidgets('alignment follows the image while zoomed', (tester) async {
      await _openSample(tester);

      final originalImage = tester.getRect(
        find.byKey(const Key('capture-image')),
      );
      await tester.tap(find.byKey(const Key('zoom-in')));
      await tester.pump();

      final image = tester.getRect(find.byKey(const Key('capture-image')));
      final rect = tester.getRect(_region('l1'));
      expect(image.width, greaterThan(originalImage.width));
      expect(rect.left, closeTo(image.left + image.width * 0.10, 0.5));
      expect(rect.right, closeTo(image.left + image.width * 0.90, 0.5));

      await tester.tapAt(_imagePoint(tester, 0.5, 0.175));
      await tester.pump();
      expect(_selectedRegions(tester), ['l1']);

      await tester.tap(find.byKey(const Key('zoom-reset')));
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const Key('capture-image'))),
        originalImage,
      );
    });

    testWidgets('tapping where a region is drawn selects it', (tester) async {
      await _openSample(tester);

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
      await pumpApp(tester, worker: worker);
      await openImage(tester);

      final image = tester.getRect(find.byKey(const Key('capture-image')));
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
      await pumpApp(tester, worker: FakeWorker([characterSampleResult()]));
      await openImage(tester);

      await tester.tapAt(_imagePoint(tester, 0.25, 0.20));
      await tester.pump();
      await tester.tap(find.byKey(const Key('copy-selection')));
      await tester.pump();

      expect(await _clipboardText(), 'b');
      expect(find.byKey(const Key('ocr-character-line-l1')), findsOneWidget);
    });

    testWidgets(
      'single, double, and triple click select character, word, line',
      (tester) async {
        await pumpApp(tester, worker: FakeWorker([wordCharacterResult()]));
        await openImage(tester);
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

    testWidgets('character hit testing stays aligned after zoom', (
      tester,
    ) async {
      await pumpApp(tester, worker: FakeWorker([characterSampleResult()]));
      await openImage(tester);
      await tester.tap(find.byKey(const Key('zoom-in')));
      await tester.pump();

      await tester.tapAt(_imagePoint(tester, 0.35, 0.20));
      await tester.pump();
      await tester.tap(find.byKey(const Key('copy-selection')));
      await tester.pump();

      expect(await _clipboardText(), 'c');
    });

    testWidgets('empty space inside a line box clears character selection', (
      tester,
    ) async {
      await pumpApp(tester, worker: FakeWorker([sparseCharacterResult()]));
      await openImage(tester);
      await tester.tapAt(_imagePoint(tester, 0.15, 0.20));
      await tester.pump();

      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('copy-selection')))
            .onPressed,
        isNotNull,
      );

      await tester.tapAt(_imagePoint(tester, 0.30, 0.20));
      await tester.pump();

      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('copy-selection')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('dragging empty image space pans while zoomed', (tester) async {
      await pumpApp(tester, worker: FakeWorker([characterSampleResult()]));
      await openImage(tester);
      await tester.tap(find.byKey(const Key('zoom-in')));
      await tester.tap(find.byKey(const Key('zoom-in')));
      await tester.pump();

      final before = tester.getRect(find.byKey(const Key('capture-image')));
      final canvas = tester.getRect(find.byKey(const Key('capture-canvas')));
      await tester.dragFrom(
        Offset(canvas.center.dx, canvas.bottom - 80),
        const Offset(-100, -80),
      );
      await tester.pump();
      final after = tester.getRect(find.byKey(const Key('capture-image')));

      expect(after.topLeft, isNot(before.topLeft));
    });

    testWidgets('dragging across characters copies the exact partial range', (
      tester,
    ) async {
      await pumpApp(tester, worker: FakeWorker([characterSampleResult()]));
      await openImage(tester);

      final start = _imagePoint(tester, 0.225, 0.20);
      final end = _imagePoint(tester, 0.475, 0.20);
      await tester.dragFrom(start, end - start);
      await tester.pump();
      await tester.tap(find.byKey(const Key('copy-selection')));
      await tester.pump();

      expect(await _clipboardText(), 'bcd');
    });

    testWidgets('backward dragging spans lines in reading order', (
      tester,
    ) async {
      await pumpApp(tester, worker: FakeWorker([multilineCharacterResult()]));
      await openImage(tester);

      final start = _imagePoint(tester, 0.275, 0.50);
      final end = _imagePoint(tester, 0.125, 0.20);
      await tester.dragFrom(start, end - start);
      await tester.pump();
      await tester.tap(find.byKey(const Key('copy-selection')));
      await tester.pump();

      expect(await _clipboardText(), 'ab\ncd');
    });

    testWidgets('arrow keys replace and extend the character selection', (
      tester,
    ) async {
      await pumpApp(tester, worker: FakeWorker([characterSampleResult()]));
      await openImage(tester);
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
      await pumpApp(tester, worker: FakeWorker([characterSampleResult()]));
      await openImage(tester);
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
      await pumpApp(tester, worker: FakeWorker([characterSampleResult()]));
      await openImage(tester);

      final node = tester.getSemantics(
        find.byKey(const Key('ocr-character-line-l1')),
      );
      expect(node.label, contains('abcd'));
      expect(node.label, contains('Character selection available'));
      expect(node.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('clicking a region selects it and its text row together', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _openSample(tester);

      await _tapRegion(tester, 'l2');
      await tester.pump();

      expect(_selectedRegions(tester), ['l2']);
      expect(_selectedRows(tester), ['l2']);
      handle.dispose();
    });

    testWidgets('clicking another region replaces the selection', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _openSample(tester);

      await _tapRegion(tester, 'l1');
      await _tapRegion(tester, 'l3');
      await tester.pump();

      expect(_selectedRegions(tester), ['l3']);
      expect(_selectedRows(tester), ['l3']);
      handle.dispose();
    });

    testWidgets('shift-click extends a contiguous range in both directions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _openSample(tester);

      await _tapRegion(tester, 'l1');
      await _shiftTapRegion(tester, 'l3');
      expect(_selectedRegions(tester), ['l1', 'l2', 'l3']);
      expect(_selectedRows(tester), ['l1', 'l2', 'l3']);

      await _tapRegion(tester, 'l3');
      await _shiftTapRegion(tester, 'l2');
      expect(_selectedRegions(tester), ['l2', 'l3']);
      handle.dispose();
    });

    testWidgets('clicking empty canvas clears the selection', (tester) async {
      final handle = tester.ensureSemantics();
      await _openSample(tester);
      await _tapRegion(tester, 'l1');
      await tester.pump();

      final canvas = tester.getRect(find.byKey(const Key('capture-canvas')));
      await tester.tapAt(canvas.topLeft + const Offset(4, 4));
      await tester.pump();

      expect(_selectedRegions(tester), isEmpty);
      expect(_selectedRows(tester), isEmpty);
      handle.dispose();
    });

    testWidgets('regions are focusable and keyboard activatable', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _openSample(tester);

      final focusNode = Focus.of(
        tester.element(
          find
              .descendant(
                of: _region('l2'),
                matching: find.byType(GestureDetector),
              )
              .first,
        ),
      );
      focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(_selectedRegions(tester), ['l2']);
      handle.dispose();
    });

    testWidgets('regions are exposed to assistive technology with their text', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _openSample(tester);

      final node = tester.getSemantics(_region('l1'));
      expect(node.label, contains('Alpha line'));
      expect(node.flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });

  group('copying', () {
    testWidgets('Copy selection is enabled only while lines are selected', (
      tester,
    ) async {
      await _openSample(tester);

      bool enabled(String key) =>
          tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed !=
          null;

      expect(enabled('copy-selection'), isFalse);
      expect(enabled('copy-all'), isTrue);

      await _tapRegion(tester, 'l1');
      await tester.pump();
      expect(enabled('copy-selection'), isTrue);

      await tester.tapAt(
        tester.getRect(find.byKey(const Key('capture-canvas'))).topLeft +
            const Offset(4, 4),
      );
      await tester.pump();
      expect(enabled('copy-selection'), isFalse);
      expect(enabled('copy-all'), isTrue);
    });

    testWidgets('Copy selection copies only selected lines in reading order', (
      tester,
    ) async {
      await _openSample(tester);
      await _tapRegion(tester, 'l3');
      await _shiftTapRegion(tester, 'l2');

      await tester.tap(find.byKey(const Key('copy-selection')));
      await tester.pump();

      expect(await _clipboardText(), 'Beta line\nGamma line');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Copy all copies every line in reading order', (tester) async {
      await _openSample(tester);

      await tester.tap(find.byKey(const Key('copy-all')));
      await tester.pump();

      expect(await _clipboardText(), 'Alpha line\nBeta line\nGamma line');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('copying announces short feedback that then disappears', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _openSample(tester);
      await _tapRegion(tester, 'l1');
      await _shiftTapRegion(tester, 'l2');

      await tester.tap(find.byKey(const Key('copy-selection')));
      await tester.pump();
      expect(find.text('Copied 2 lines'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.text('Copied 2 lines'))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );

      await tester.tap(find.byKey(const Key('copy-all')));
      await tester.pump();
      expect(find.text('Copied all 3 lines'), findsOneWidget);
      expect(find.text('Copied 2 lines'), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Copied all 3 lines'), findsNothing);
      handle.dispose();
    });

    testWidgets('a single line is described in the singular', (tester) async {
      await _openSample(tester);
      await _tapRegion(tester, 'l1');
      await tester.tap(find.byKey(const Key('copy-selection')));
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
      await _openSample(tester);

      await tester.tap(find.byKey(const Key('copy-all')));
      await tester.pump();

      expect(find.text('Could not copy. Try again.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('session lifecycle', () {
    testWidgets('New image discards the session and returns to the empty '
        'state', (tester) async {
      final worker = FakeWorker([sampleResult()]);
      await pumpApp(tester, worker: worker);
      await openImage(tester);
      await _tapRegion(tester, 'l1');
      await tester.pump();

      await tester.tap(find.byKey(const Key('new-image')));
      await tester.pump();

      expect(find.text('Open an image'), findsOneWidget);
      expect(_region('l1'), findsNothing);
      expect(find.text('Alpha line'), findsNothing);

      // A fresh session starts with nothing selected.
      final handle = tester.ensureSemantics();
      await openImage(tester);
      expect(worker.calls, 2);
      expect(_selectedRegions(tester), isEmpty);
      expect(_selectedRows(tester), isEmpty);
      handle.dispose();
    });

    testWidgets('opening another image discards the previous selection', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final worker = FakeWorker([sampleResult()]);
      await pumpApp(tester, worker: worker);
      await openImage(tester);
      await _tapRegion(tester, 'l1');
      await tester.pump();
      expect(_selectedRegions(tester), ['l1']);

      await openImage(tester);

      expect(worker.calls, 2);
      expect(_selectedRegions(tester), isEmpty);
      expect(_selectedRows(tester), isEmpty);
      handle.dispose();
    });

    testWidgets('cancelling the picker keeps the current session', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final picker = FakePicker();
      final worker = FakeWorker([sampleResult()]);
      await pumpApp(tester, picker: picker, worker: worker);
      await openImage(tester);
      await _tapRegion(tester, 'l1');
      await tester.pump();

      picker.path = null;
      await openImage(tester);

      expect(worker.calls, 1);
      expect(_selectedRegions(tester), ['l1']);
      handle.dispose();
    });
  });
}
