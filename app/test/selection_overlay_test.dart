import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/app/app_lifecycle.dart';
import 'package:kiriglyph/app/app_shell.dart';
import 'package:kiriglyph/app/window_surface.dart';
import 'package:kiriglyph/capture/screen_capture.dart';
import 'package:kiriglyph/capture/session_image_store.dart';
import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/overlay/display_layout.dart';
import 'package:kiriglyph/overlay/overlay_frame.dart';
import 'package:kiriglyph/overlay/selection_overlay.dart';
import 'package:kiriglyph/protocol/protocol_error.dart';
import 'package:kiriglyph/providers.dart';
import 'package:kiriglyph/selection/region_selection_provider.dart';

import 'support/fake_subject_segmenter.dart';
import 'support/overlay_fakes.dart';

OcrResult sampleResult() => resultWith([
  _line('l3', 'Gamma line', 2, 20, 70, 60, 85),
  _line('l1', 'Alpha line', 0, 20, 10, 180, 25),
  _line('l2', 'Beta line', 1, 20, 40, 120, 55),
]);

OcrResult resultWith(List<TextRegion> regions) => OcrResult(
  imageWidth: 200,
  imageHeight: 100,
  fullText: '',
  regions: regions,
  timingsMs: const TimingsMs(total: 420),
);

TextRegion _line(
  String id,
  String text,
  int order,
  double left,
  double top,
  double right,
  double bottom,
) => TextRegion(
  id: id,
  level: TextRegionLevel.line,
  text: text,
  polygon: [
    Point(x: left, y: top),
    Point(x: right, y: top),
    Point(x: right, y: bottom),
    Point(x: left, y: bottom),
  ],
  confidence: 1,
  readingOrder: order,
);

void main() {
  late Directory root;
  late Directory pictures;
  late Directory runtime;
  late FakeSilentPortal portal;
  late FakeShell shell;
  late FakeFrameCodec codec;
  late ControlledWorker worker;
  late FakeSubjectSegmenter subjectSegmenter;
  late ProviderContainer container;
  late List<OverlayPhase> phases;
  late ui.Image image;

  setUpAll(() async {
    image = await createTestImage(width: 4, height: 2);
  });

  setUp(() {
    root = Directory.systemTemp.createTempSync('selection-overlay-');
    pictures = Directory('${root.path}/Pictures')..createSync();
    runtime = Directory('${root.path}/runtime')..createSync();
    portal = FakeSilentPortal(pictures);
    shell = FakeShell();
    codec = FakeFrameCodec(image);
    worker = ControlledWorker(sampleResult());
    subjectSegmenter = FakeSubjectSegmenter();
    container = ProviderContainer(
      overrides: [
        appShellProvider.overrideWithValue(shell),
        silentScreenCaptureProvider.overrideWithValue(portal),
        sessionImageStoreProvider.overrideWithValue(
          SessionImageStore(root: runtime),
        ),
        overlayFrameCodecProvider.overrideWithValue(codec),
        ocrWorkerProvider.overrideWithValue(worker),
        subjectSegmenterProvider.overrideWithValue(subjectSegmenter),
        overlayTimeoutsProvider.overrideWithValue(
          const OverlayTimeouts(
            content: Duration(milliseconds: 200),
            failureMessage: Duration(milliseconds: 50),
          ),
        ),
      ],
    );
    phases = [];
    container.listen(
      selectionOverlayProvider.select((s) => s.phase),
      (_, next) => phases.add(next),
    );
  });

  tearDown(() {
    container.dispose();
    root.deleteSync(recursive: true);
  });

  SelectionOverlayController overlay() =>
      container.read(selectionOverlayProvider.notifier);
  SelectionOverlayState state() => container.read(selectionOverlayProvider);
  List<FileSystemEntity> privateFiles() =>
      runtime.listSync(recursive: true).whereType<File>().toList();

  test('a selection freezes the display under the window and recognizes '
      'only that display', () async {
    expect(await overlay().start(), isTrue);

    expect(phases, [
      OverlayPhase.capturing,
      OverlayPhase.placing,
      OverlayPhase.recognizing,
      OverlayPhase.ready,
    ]);
    expect(shell.events, ['prepare', 'show', 'reveal']);
    expect(pictures.listSync(), isEmpty, reason: 'portal file deleted');
    expect(codec.decoded.single, [1], reason: 'decoded in memory');
    expect(codec.crops.single.source, const PixelRect(0, 0, 200, 100));
    expect(state().frame, isNotNull);
    expect(state().ocrResult, isNotNull);

    final ocrPath = worker.paths.single;
    expect(ocrPath, startsWith(runtime.path));
    expect(File(ocrPath).readAsBytesSync(), FakeFrameCodec.encodedBytes);
    expect(privateFiles(), hasLength(1), reason: 'only the crop is stored');
    expect(
      container.read(regionSelectionProvider).regions,
      hasLength(3),
      reason: 'the overlay result drives selection',
    );
  });

  test('the target display chooses the crop', () async {
    shell.placement = DisplayPlacement(
      monitors: twoDisplays.monitors,
      targetIndex: 1,
    );
    await overlay().start();
    expect(codec.crops.single.source, const PixelRect(200, 0, 100, 50));
  });

  test('repeated selections while capturing or shown are ignored', () async {
    portal.gate = Completer<void>();
    final first = overlay().start();
    expect(await overlay().start(), isFalse);
    portal.gate!.complete();
    expect(await first, isTrue);
    expect(state().phase, OverlayPhase.ready);
    expect(await overlay().start(), isFalse);

    expect(portal.calls, 1);
    expect(shell.count('show'), 1);
    expect(worker.paths, hasLength(1));
  });

  test('dismissing hides the overlay and discards frame, text and the '
      'private copy', () async {
    await overlay().start();
    await overlay().dismiss();

    expect(state().phase, OverlayPhase.idle);
    expect(state().frame, isNull);
    expect(state().ocrResult, isNull);
    expect(container.read(regionSelectionProvider).regions, isEmpty);
    expect(shell.events.last, 'hide');
    expect(privateFiles(), isEmpty);
    expect(subjectSegmenter.closed, isTrue);

    subjectSegmenter.closed = false;
    expect(await overlay().start(), isTrue, reason: 'a new selection works');
    expect(state().phase, OverlayPhase.ready);
  });

  test(
    'export interaction keeps overlay visible and ignores focus loss',
    () async {
      await overlay().start();

      await overlay().beginExportInteraction();
      expect(state().exportInProgress, isTrue);
      expect(shell.events.last, 'suppress-focus');

      await overlay().handleFocusLost();
      expect(state().phase, OverlayPhase.ready);
      expect(privateFiles(), hasLength(1));

      await overlay().completeExportInteraction(dismissOverlay: false);
      expect(state().exportInProgress, isFalse);
      expect(shell.events.last, 'unsuppress-focus');
    },
  );

  test('direct export completion keeps the session alive', () async {
    await overlay().start();

    await overlay().beginExportInteraction();
    await overlay().completeExportInteraction(dismissOverlay: false);

    expect(state().phase, OverlayPhase.ready);
    expect(privateFiles(), hasLength(1));
    expect(
      shell.events,
      containsAllInOrder(['suppress-focus', 'unsuppress-focus']),
    );
  });

  test('a result arriving after dismissal is discarded', () async {
    worker.next = null;
    final start = overlay().start();
    await until(() => worker.pending.isNotEmpty);
    expect(state().phase, OverlayPhase.recognizing);

    worker.inFlightCancels = 0;
    await overlay().dismiss();
    worker.pending.single.complete(sampleResult());
    await start;

    expect(state().phase, OverlayPhase.idle);
    expect(state().ocrResult, isNull);
    expect(privateFiles(), isEmpty);
    await until(() => worker.inFlightCancels > 0);
    expect(worker.inFlightCancels, 1, reason: 'OCR request was dropped');
    expect(worker.restarts, 0, reason: 'warm OCR worker stays alive');
  });

  test('missing permission opens onboarding instead of the overlay', () async {
    portal.status = ScreenCaptureStatus.ended;

    await overlay().start();

    expect(state().phase, OverlayPhase.idle);
    expect(shell.events, ['prepare', 'present']);
    expect(container.read(selectionNoticeProvider), permissionNotice);
    expect(worker.paths, isEmpty);
  });

  test('a portal failure shows a brief message, then closes', () async {
    portal.status = ScreenCaptureStatus.failed;

    await overlay().start();
    expect(state().phase, OverlayPhase.failed);
    expect(state().frame, isNull);
    expect(state().message, contains('Screen capture failed'));

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(state().phase, OverlayPhase.idle);
    expect(shell.events, ['prepare', 'show', 'reveal', 'hide']);
  });

  test(
    'no text stays ready, starts subject embedding, and does not auto close',
    () async {
      worker.next = resultWith(const []);

      await overlay().start();
      expect(state().phase, OverlayPhase.ready);
      expect(state().frame, isNotNull);
      expect(state().ocrResult, isNotNull);
      expect(state().ocrResult!.regions, isEmpty);
      expect(state().subjectEmbedding, isNotNull);
      expect(subjectSegmenter.embedCalls, 1);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(state().phase, OverlayPhase.ready);
      expect(privateFiles(), hasLength(1));
    },
  );

  test('worker no_text stays ready and starts subject embedding', () async {
    worker.next = null;
    worker.error = WorkerError(code: 'no_text', message: 'no text');

    await overlay().start();

    expect(state().phase, OverlayPhase.ready);
    expect(state().ocrResult, isNotNull);
    expect(state().ocrResult!.regions, isEmpty);
    expect(state().ocrResult!.fullText, isEmpty);
    expect(state().subjectEmbedding, isNotNull);
    expect(subjectSegmenter.embedCalls, 1);
    expect(state().message, isNull);
  });

  test('OCR failures show safe messages', () async {
    worker.error = const WorkerProcessError(
      kind: WorkerFailureKind.timeout,
      message: 'secret detail',
    );
    worker.next = null;

    await overlay().start();

    expect(state().phase, OverlayPhase.failed);
    expect(state().message, 'Text recognition took too long. Try again.');
  });

  test('a layout that does not match the capture is reported', () async {
    codec.width = 1920;
    codec.height = 1080;

    await overlay().start();

    expect(state().phase, OverlayPhase.failed);
    expect(state().message, 'This display layout is not supported yet.');
    expect(worker.paths, isEmpty);
  });

  test(
    'a failed placement closes the overlay and reports in the window',
    () async {
      shell.placementError = const OverlayPlacementException(
        'placement_timeout',
      );

      await overlay().start();

      expect(state().phase, OverlayPhase.idle);
      expect(shell.events, ['prepare', 'show', 'hide', 'present']);
      expect(container.read(selectionNoticeProvider), overlayStartNotice);
    },
  );

  test('content that never becomes ready times out', () async {
    shell.placementGate = Completer<DisplayPlacement>();

    final start = overlay().start();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await start;

    expect(state().phase, OverlayPhase.idle);
    expect(shell.events, ['prepare', 'show', 'hide', 'present']);
    expect(container.read(selectionNoticeProvider), overlayStartNotice);
    expect(privateFiles(), isEmpty);
  });

  test('an unreadable capture is reported in the overlay', () async {
    codec.failDecode = true;

    await overlay().start();

    expect(state().phase, OverlayPhase.failed);
    expect(state().message, 'The screenshot could not be read.');
  });

  group('app lifecycle', () {
    test('warms the worker and routes selection commands', () async {
      await AppLifecycle(container).start();
      expect(worker.restarts, 1);

      await shell.handler!(AppCommand.select);
      expect(state().phase, OverlayPhase.ready);

      await shell.handler!(AppCommand.overlayFocusLost);
      expect(state().phase, OverlayPhase.idle);
      expect(shell.events.last, 'hide');
    });

    test(
      'presenting the window paints the main screen before it maps',
      () async {
        await AppLifecycle(container).start();
        container.read(mainWindowShownProvider.notifier).hidden();
        expect(container.read(mainWindowShownProvider), isFalse);

        await shell.handler!(AppCommand.presented);

        expect(container.read(mainWindowShownProvider), isTrue);
        expect(shell.events, ['present']);
      },
    );

    test('closing or quitting dismisses an open overlay', () async {
      await AppLifecycle(container).start();
      for (final command in [AppCommand.hidden, AppCommand.quit]) {
        await shell.handler!(AppCommand.select);
        await shell.handler!(command);
        expect(state().phase, OverlayPhase.idle, reason: '$command');
        expect(privateFiles(), isEmpty);
        subjectSegmenter.closed = false;
      }
    });
  });
}
