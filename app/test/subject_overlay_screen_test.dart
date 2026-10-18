import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/app/app_shell.dart';
import 'package:kiriglyph/capture/session_image_store.dart';
import 'package:kiriglyph/export/subject_cutout.dart';
import 'package:kiriglyph/export/subject_export.dart';
import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/overlay/display_layout.dart';
import 'package:kiriglyph/overlay/overlay_frame.dart';
import 'package:kiriglyph/overlay/selection_overlay.dart';
import 'package:kiriglyph/providers.dart';
import 'package:kiriglyph/segmentation/subject_segmenter.dart';
import 'package:kiriglyph/ui/kiriglyph_app.dart';

import 'support/fake_subject_segmenter.dart';
import 'support/overlay_fakes.dart';
import 'support/workspace_harness.dart';

class _Overlay {
  _Overlay(this.container, this.segmenter);

  final ProviderContainer container;
  final FakeSubjectSegmenter segmenter;
}

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('subject-overlay-');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  Future<_Overlay> openOverlay(
    WidgetTester tester, {
    FakeSubjectSegmenter? segmenter,
    FakeSubjectExportController? exporter,
    Size size = const Size(800, 400),
    OcrResult? result,
  }) async {
    final ocr = result ?? sampleResult();
    final image = await tester.runAsync(
      () => createTestImage(width: ocr.imageWidth, height: ocr.imageHeight),
    );
    final pictures = Directory('${root.path}/Pictures')..createSync();
    final runtime = Directory('${root.path}/runtime')..createSync();
    final shell = FakeShell()
      ..placement = DisplayPlacement(
        monitors: [
          LogicalMonitor(
            x: 0,
            y: 0,
            width: ocr.imageWidth,
            height: ocr.imageHeight,
          ),
        ],
        targetIndex: 0,
      );
    final fakeSegmenter = segmenter ?? FakeSubjectSegmenter();
    await pumpApp(
      tester,
      size: size,
      worker: ControlledWorker(ocr),
      overrides: [
        appShellProvider.overrideWithValue(shell),
        silentScreenCaptureProvider.overrideWithValue(
          FakeSilentPortal(pictures),
        ),
        sessionImageStoreProvider.overrideWithValue(
          SessionImageStore(root: runtime),
        ),
        overlayFrameCodecProvider.overrideWithValue(
          FakeFrameCodec(
            image!,
            width: ocr.imageWidth,
            height: ocr.imageHeight,
          ),
        ),
        subjectSegmenterProvider.overrideWithValue(fakeSegmenter),
        if (exporter != null)
          subjectExportControllerProvider.overrideWithValue(exporter),
      ],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(KiriglyphApp)),
    );
    await tester.runAsync(() async {
      unawaited(container.read(selectionOverlayProvider.notifier).start());
      await until(
        () =>
            container.read(selectionOverlayProvider).phase ==
            OverlayPhase.ready,
      );
    });
    await tester.pump();
    return _Overlay(container, fakeSegmenter);
  }

  Future<void> subjectMode(
    WidgetTester tester,
    FakeSubjectSegmenter segmenter,
  ) async {
    await tester.runAsync(() async {
      await until(() => segmenter.embedCalls > 0);
    });
    await tester.pump();
  }

  testWidgets('unified toolbar has text actions only', (tester) async {
    await openOverlay(tester);

    expect(find.text('Drag across text, or click an object'), findsOneWidget);
    expect(find.byKey(const Key('overlay-mode-toggle')), findsNothing);
    expect(find.byKey(const Key('subject-action-chip')), findsNothing);
    expect(find.byKey(const Key('overlay-copy')), findsOneWidget);
    expect(find.byKey(const Key('overlay-copy-all')), findsOneWidget);
  });

  testWidgets('empty text result invites object selection', (tester) async {
    final overlay = await openOverlay(tester, result: resultWith(const []));

    expect(
      find.text('No text found - click or draw around an object'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('overlay-copy')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('overlay-copy-all')))
          .onPressed,
      isNull,
    );

    await subjectMode(tester, overlay.segmenter);
    await tester.tapAt(const Offset(40, 20));
    await tester.pump();

    expect(overlay.segmenter.prompts, hasLength(1));
    expect(find.byKey(const Key('subject-chip-status')), findsOneWidget);
  });

  testWidgets('subject toolbar copies and saves with shortcuts', (
    tester,
  ) async {
    final exporter = FakeSubjectExportController();
    final overlay = await openOverlay(tester, exporter: exporter);
    await subjectMode(tester, overlay.segmenter);

    expect(find.byKey(const Key('overlay-copy-subject-image')), findsNothing);
    expect(find.byKey(const Key('overlay-save-subject-png')), findsNothing);

    await tester.tapAt(const Offset(40, 20));
    await tester.pump();
    expect(find.byKey(const Key('subject-chip-status')), findsOneWidget);
    expect(find.byKey(const Key('subject-action-chip')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(exporter.copyCalls, 1);
    expect(find.text('Copied image'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(exporter.saveCalls, 1);
    expect(
      overlay.container.read(selectionOverlayProvider).phase,
      OverlayPhase.ready,
      reason: 'direct save keeps the overlay open',
    );
    expect(find.textContaining('Saved to Pictures/'), findsOneWidget);
  });

  testWidgets('cancelled save restores the overlay without a failure message', (
    tester,
  ) async {
    final exporter = FakeSubjectExportController()
      ..saveOutcome = const SubjectExportOutcome(
        SubjectExportOutcomeKind.cancelled,
      );
    final overlay = await openOverlay(tester, exporter: exporter);
    await subjectMode(tester, overlay.segmenter);
    await tester.tapAt(const Offset(40, 20));
    await tester.pump();

    await tester.tap(find.byKey(const Key('overlay-save-subject-png')));
    await tester.pump();

    expect(exporter.saveCalls, 1);
    expect(
      overlay.container.read(selectionOverlayProvider).phase,
      OverlayPhase.ready,
    );
    expect(find.byKey(const Key('overlay-toolbar')), findsOneWidget);
    expect(find.text('Could not save PNG there.'), findsNothing);
  });

  testWidgets('dismiss during stuck export clears busy for next session', (
    tester,
  ) async {
    final exporter = HangingSubjectExportController();
    final overlay = await openOverlay(tester, exporter: exporter);
    await subjectMode(tester, overlay.segmenter);
    await tester.tapAt(const Offset(40, 20));
    await tester.pump();

    await tester.tap(find.byKey(const Key('overlay-save-subject-png')));
    await tester.pump();
    expect(find.text('Exporting subject…'), findsWidgets);

    await tester.runAsync(
      () => overlay.container.read(selectionOverlayProvider.notifier).dismiss(),
    );
    await tester.pump();
    await tester.runAsync(() async {
      unawaited(
        overlay.container.read(selectionOverlayProvider.notifier).start(),
      );
      await until(
        () =>
            overlay.container.read(selectionOverlayProvider).phase ==
            OverlayPhase.ready,
      );
    });
    await tester.pump();

    expect(find.text('Exporting subject…'), findsNothing);
    exporter.completer.complete(
      const SubjectExportOutcome(SubjectExportOutcomeKind.cancelled),
    );
    await tester.pump();
  });

  testWidgets('subject chip actions participate in tab order', (tester) async {
    final overlay = await openOverlay(
      tester,
      exporter: FakeSubjectExportController(),
    );
    await subjectMode(tester, overlay.segmenter);
    await tester.tapAt(const Offset(40, 20));
    await tester.pump();

    expect(find.byKey(const Key('overlay-copy-subject-image')), findsOneWidget);
    expect(find.byKey(const Key('overlay-save-subject-png')), findsOneWidget);
    expect(find.byKey(const Key('overlay-remove-subject')), findsOneWidget);
    expect(find.byKey(const Key('overlay-close')), findsOneWidget);
  });

  testWidgets('click, modifier click, and lasso send source-image prompts', (
    tester,
  ) async {
    final overlay = await openOverlay(tester);
    await subjectMode(tester, overlay.segmenter);

    await tester.tapAt(const Offset(40, 20));
    await tester.pump();
    expect(overlay.segmenter.prompts.last.points.single.x, 10);
    expect(overlay.segmenter.prompts.last.points.single.y, 5);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(const Offset(760, 160));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(overlay.segmenter.prompts, hasLength(2));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.tapAt(const Offset(760, 200));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(overlay.segmenter.prompts, hasLength(3));

    await tester.tap(find.text('Free draw'));
    await tester.pump();
    final gesture = await tester.createGesture();
    await gesture.down(const Offset(320, 120));
    await gesture.moveTo(const Offset(520, 120));
    await gesture.moveTo(const Offset(520, 260));
    await gesture.moveTo(const Offset(320, 260));
    await gesture.up();
    await tester.pump();

    final prompt = overlay.segmenter.prompts.last;
    expect(prompt.box, isNotNull);
    expect(prompt.polygon, isNotNull);
    expect(prompt.box!.x, 80);
    expect(prompt.box!.y, 30);
  });

  testWidgets('point prompts stay aligned at 1.25x fitted-image scale', (
    tester,
  ) async {
    final overlay = await openOverlay(
      tester,
      size: const Size(1000, 500),
      result: OcrResult(
        imageWidth: 800,
        imageHeight: 400,
        fullText: 'subject',
        regions: [box('l1', 'subject', 0, 20, 20, 120, 50)],
        timingsMs: const TimingsMs(total: 1),
      ),
    );
    await subjectMode(tester, overlay.segmenter);

    await tester.tapAt(const Offset(125, 62.5));
    await tester.pump();

    expect(overlay.segmenter.prompts.last.points.single.x, 100);
    expect(overlay.segmenter.prompts.last.points.single.y, 50);
  });

  testWidgets('keyboard object cursor lifts an object with O and Enter', (
    tester,
  ) async {
    final overlay = await openOverlay(tester);
    await subjectMode(tester, overlay.segmenter);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.pump();
    expect(find.byKey(const Key('object-keyboard-cursor')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(overlay.segmenter.prompts, hasLength(1));
    expect(overlay.segmenter.prompts.single.points.single.x, greaterThan(5));
  });

  testWidgets('Clear cancels in-flight work and closes segmenter on dismiss', (
    tester,
  ) async {
    final overlay = await openOverlay(tester);
    await subjectMode(tester, overlay.segmenter);
    await tester.tapAt(const Offset(40, 20));
    await tester.pump();

    await tester.tap(find.byKey(const Key('overlay-remove-subject')));
    await tester.pump();
    expect(overlay.segmenter.cancelCalls, greaterThanOrEqualTo(1));
    expect(find.text('Drag across text, or click an object'), findsOneWidget);

    await tester.runAsync(
      () => overlay.container.read(selectionOverlayProvider.notifier).dismiss(),
    );
    await tester.pump();
    expect(overlay.segmenter.closed, isTrue);
  });

  testWidgets('model-missing failures show the fetch command', (tester) async {
    final overlay = await openOverlay(
      tester,
      segmenter: FakeSubjectSegmenter(
        promptError: const SubjectSegmentationException(
          kind: SubjectFailureKind.modelMissing,
          message: 'missing',
          command: 'kiriglyph-fetch-models',
        ),
      ),
    );
    await subjectMode(tester, overlay.segmenter);
    await tester.tapAt(const Offset(40, 20));
    await tester.pump();

    expect(find.textContaining('kiriglyph-fetch-models'), findsOneWidget);
  });

  for (final (name, result, message) in [
    (
      'empty',
      _result(outcome: SubjectMaskOutcome.empty, areaFraction: 0, bounds: null),
      'No object found here. Try drawing around it.',
    ),
    (
      'suspect full image',
      _result(outcome: SubjectMaskOutcome.suspectFullImage, areaFraction: 0.98),
      'That selected almost the whole screen',
    ),
    (
      'touches edge',
      _result(touchesEdge: true),
      'Subject touches the screen edge',
    ),
    ('multiple components', _result(componentCount: 3), '3 separate pieces'),
  ]) {
    testWidgets('$name outcome shows a recoverable status', (tester) async {
      final overlay = await openOverlay(
        tester,
        segmenter: FakeSubjectSegmenter(result: result),
      );
      await subjectMode(tester, overlay.segmenter);
      await tester.tapAt(const Offset(40, 20));
      await tester.pump();

      expect(find.textContaining(message), findsOneWidget);
    });
  }

  testWidgets('mask result is exposed in semantics', (tester) async {
    final handle = tester.ensureSemantics();
    final overlay = await openOverlay(tester);
    await subjectMode(tester, overlay.segmenter);
    await tester.tapAt(const Offset(40, 20));
    await tester.pump();

    final semantics = tester.getSemantics(
      find.byKey(const Key('subject-overlay-layer')),
    );
    expect(
      semantics.value,
      'Subject selected, covers 40 percent of the screen',
    );
    handle.dispose();
  });
}

SubjectMaskResult _result({
  SubjectMaskOutcome outcome = SubjectMaskOutcome.ok,
  double areaFraction = 0.4,
  SubjectRect? bounds = const SubjectRect(x: 1, y: 1, width: 6, height: 5),
  bool touchesEdge = false,
  int componentCount = 1,
}) => SubjectMaskResult(
  imageWidth: 10,
  imageHeight: 8,
  mask: const SubjectMaskReference(
    path: '/tmp/fake-mask.png',
    byteLength: 1,
    sha256: '0',
  ),
  bounds: bounds,
  stats: SubjectMaskStats(
    outcome: outcome,
    areaFraction: areaFraction,
    bounds: bounds,
    touchesEdge: SubjectEdgeTouches(
      left: touchesEdge,
      top: false,
      right: false,
      bottom: false,
    ),
    components: SubjectComponentStats(
      count: componentCount,
      largestBounds: bounds,
    ),
  ),
  timings: const SubjectSegmentationTimings(promptMs: 3),
  confidence: 0.8,
);

class FakeSubjectExportController extends SubjectExportController {
  FakeSubjectExportController()
    : super(
        clipboard: _NoopClipboard(),
        savePort: _NoopSavePort(),
        codec: _NoopCodec(),
      );

  int copyCalls = 0;
  int saveCalls = 0;
  SubjectExportOutcome copyOutcome = const SubjectExportOutcome(
    SubjectExportOutcomeKind.copied,
  );
  SubjectExportOutcome saveOutcome = const SubjectExportOutcome(
    SubjectExportOutcomeKind.saved,
    savedName: 'kiriglyph-20260102-030405.png',
  );

  @override
  Future<SubjectExportOutcome> copy({
    required String sourceImagePath,
    required SubjectMaskResult mask,
  }) async {
    copyCalls++;
    return copyOutcome;
  }

  @override
  Future<SubjectExportOutcome> save({
    required String sourceImagePath,
    required SubjectMaskResult mask,
    String? suggestedName,
  }) async {
    saveCalls++;
    return saveOutcome;
  }
}

class HangingSubjectExportController extends FakeSubjectExportController {
  final completer = Completer<SubjectExportOutcome>();

  @override
  Future<SubjectExportOutcome> save({
    required String sourceImagePath,
    required SubjectMaskResult mask,
    String? suggestedName,
  }) {
    saveCalls++;
    return completer.future;
  }
}

class _NoopClipboard implements ClipboardImagePort {
  @override
  Future<void> copyPng(Uint8List pngBytes) async {}
}

class _NoopSavePort implements SavePngPort {
  @override
  Future<SaveDestination> chooseDestination(String suggestedName) async =>
      const SaveDestination.cancelled();
}

class _NoopCodec implements SubjectImageCodec {
  @override
  Future<RgbaImageBuffer> decodeRgba(Uint8List encoded) async =>
      throw UnimplementedError();

  @override
  Future<Uint8List> encodePng(SubjectCutoutImage image) async =>
      throw UnimplementedError();
}
