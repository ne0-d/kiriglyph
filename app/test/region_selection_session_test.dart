import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/ui/kiriglyph_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/overlay/selection_overlay.dart';
import 'package:kiriglyph/selection/region_selection_provider.dart';
import 'package:kiriglyph/worker/ocr_worker.dart';

import 'support/workspace_harness.dart';

class _SequenceWorker implements OcrWorker {
  _SequenceWorker(this.results);

  final List<OcrResult> results;
  int _next = 0;

  @override
  Future<void> cancelActive() async {}

  @override
  Future<OcrResult> recognize(String imagePath) async =>
      results[_next++ % results.length];

  @override
  Future<void> restart() async {}

  @override
  Future<void> close() async {}
}

OcrResult _result(List<String> lines) => OcrResult(
  imageWidth: kImageWidth,
  imageHeight: kImageHeight,
  fullText: lines.join('\n'),
  regions: [
    for (var i = 0; i < lines.length; i++)
      TextRegion(
        id: 'line-$i',
        level: TextRegionLevel.line,
        text: lines[i],
        polygon: const [
          Point(x: 0, y: 0),
          Point(x: 10, y: 0),
          Point(x: 10, y: 10),
          Point(x: 0, y: 10),
        ],
        confidence: 1,
        readingOrder: i,
      ),
  ],
  timingsMs: const TimingsMs(total: 5),
);

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('region-selection-');
  });

  tearDown(() => root.deleteSync(recursive: true));

  testWidgets('overlay session starts with lines in order and no selection', (
    tester,
  ) async {
    final container = await _pumpWithOverlay(
      tester,
      root,
      worker: _SequenceWorker([
        _result(['One', 'Two', 'Three']),
      ]),
    );

    final selection = container.read(regionSelectionProvider);
    expect(selection.allText, 'One\nTwo\nThree');
    expect(selection.hasSelection, isFalse);
  });

  testWidgets('selection controller applies replace, extend and clear', (
    tester,
  ) async {
    final container = await _pumpWithOverlay(
      tester,
      root,
      worker: _SequenceWorker([
        _result(['One', 'Two', 'Three']),
      ]),
    );
    final controller = container.read(regionSelectionProvider.notifier);

    controller.select('line-0');
    controller.extendTo('line-2');
    expect(
      container.read(regionSelectionProvider).selectedText,
      'One\nTwo\nThree',
    );

    controller.select('line-1');
    expect(container.read(regionSelectionProvider).selectedText, 'Two');

    controller.clear();
    expect(container.read(regionSelectionProvider).hasSelection, isFalse);
  });

  testWidgets('a new overlay discards the previous selection', (tester) async {
    final worker = _SequenceWorker([
      _result(['One', 'Two', 'Three']),
      _result(['Four', 'Five']),
    ]);
    final container = await _pumpWithOverlay(tester, root, worker: worker);
    container.read(regionSelectionProvider.notifier).select('line-1');

    await tester.runAsync(
      () => container.read(selectionOverlayProvider.notifier).dismiss(),
    );
    await tester.pump();
    await restartOverlayCanvas(tester, container);
    final selection = container.read(regionSelectionProvider);
    expect(selection.allText, 'Four\nFive');
    expect(selection.hasSelection, isFalse);
  });

  testWidgets('dismissing the overlay clears the selection', (tester) async {
    final container = await _pumpWithOverlay(
      tester,
      root,
      worker: _SequenceWorker([
        _result(['One']),
      ]),
    );
    container.read(regionSelectionProvider.notifier).select('line-0');

    await tester.runAsync(
      () => container.read(selectionOverlayProvider.notifier).dismiss(),
    );
    await tester.pump();

    final selection = container.read(regionSelectionProvider);
    expect(selection.regions, isEmpty);
    expect(selection.hasSelection, isFalse);
  });
}

Future<ProviderContainer> _pumpWithOverlay(
  WidgetTester tester,
  Directory testRoot, {
  required OcrWorker worker,
}) async {
  await openOverlayCanvas(tester, testRoot: testRoot, worker: worker);
  return ProviderScope.containerOf(tester.element(find.byType(KiriglyphApp)));
}
