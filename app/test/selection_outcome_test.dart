import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/selection/selection_outcome.dart';

void main() {
  test('text wins when at least sixty percent of a line is inside', () {
    final outcome = classifySelectionOutcome(
      selection: const SelectionBounds(left: 0, top: 0, right: 70, bottom: 20),
      lines: [_line('l1', 'hello', 0, 0, 100, 20)],
    );

    expect(outcome.primary, SelectionOutcomeKind.text);
    expect(selectionTextLineCoverageThreshold, 0.60);
    expect(outcome.textLines.map((line) => line.id), ['l1']);
  });

  test('object wins only after text fails and mask fills enough selection', () {
    final outcome = classifySelectionOutcome(
      selection: const SelectionBounds(
        left: 0,
        top: 0,
        right: 100,
        bottom: 100,
      ),
      lines: [_line('caption', 'abc', 0, 90, 200, 110)],
      mask: const SelectionMaskCandidate(confident: true, areaFraction: 0.3),
    );

    expect(outcome.primary, SelectionOutcomeKind.object);
    expect(selectionObjectFillThreshold, 0.25);
  });

  test('plain image is the fallback and screenshot actions remain valid', () {
    final outcome = classifySelectionOutcome(
      selection: const SelectionBounds(
        left: 0,
        top: 0,
        right: 100,
        bottom: 100,
      ),
      lines: const [],
    );

    expect(outcome.primary, SelectionOutcomeKind.image);
    expect(outcome.canCopyScreenshot, isTrue);
    expect(outcome.canSaveScreenshot, isTrue);
  });
}

TextRegion _line(
  String id,
  String text,
  double left,
  double top,
  double right,
  double bottom,
) {
  return TextRegion(
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
    readingOrder: 0,
    ranges: const [],
  );
}
