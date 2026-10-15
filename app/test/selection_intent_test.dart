import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/selection/selection_intent.dart';

void main() {
  group('point intent', () {
    test('drag starting on text stays text', () {
      expect(
        classifyPointerDownIntent(
          startsOnText: true,
          modifiers: const SelectionModifiers(),
          isClick: false,
        ),
        isA<TextDragIntent>(),
      );
    });

    test(
      'single click on text clears, double and triple remain text clicks',
      () {
        expect(
          classifyPointerDownIntent(
            startsOnText: true,
            modifiers: const SelectionModifiers(),
            isClick: true,
          ),
          isA<ClearSelectionIntent>(),
        );
        expect(
          classifyPointerDownIntent(
            startsOnText: true,
            modifiers: const SelectionModifiers(),
            isClick: true,
            clickCount: 2,
          ),
          isA<TextClickIntent>().having(
            (intent) => intent.clickCount,
            'count',
            2,
          ),
        );
        expect(
          classifyPointerDownIntent(
            startsOnText: true,
            modifiers: const SelectionModifiers(),
            isClick: true,
            clickCount: 3,
          ),
          isA<TextClickIntent>().having(
            (intent) => intent.clickCount,
            'count',
            3,
          ),
        );
      },
    );

    test('off-text clicks map to object prompt intents', () {
      expect(
        classifyPointerDownIntent(
          startsOnText: false,
          modifiers: const SelectionModifiers(),
          isClick: true,
        ),
        isA<ObjectClickIntent>(),
      );
      expect(
        classifyPointerDownIntent(
          startsOnText: false,
          modifiers: const SelectionModifiers(shift: true),
          isClick: true,
        ),
        isA<ObjectAddForegroundIntent>(),
      );
      expect(
        classifyPointerDownIntent(
          startsOnText: false,
          modifiers: const SelectionModifiers(alt: true),
          isClick: true,
        ),
        isA<ObjectAddBackgroundIntent>(),
      );
      expect(
        classifyPointerDownIntent(
          startsOnText: false,
          modifiers: const SelectionModifiers(secondary: true),
          isClick: true,
        ),
        isA<ObjectAddBackgroundIntent>(),
      );
    });

    test('Ctrl forces object over text', () {
      expect(
        classifyPointerDownIntent(
          startsOnText: true,
          modifiers: const SelectionModifiers(control: true),
          isClick: true,
        ),
        isA<ObjectClickIntent>(),
      );
      expect(
        classifyPointerDownIntent(
          startsOnText: true,
          modifiers: const SelectionModifiers(control: true),
          isClick: false,
        ),
        isA<LoopAsObjectIntent>(),
      );
    });
  });

  group('text hit testing', () {
    test('accepts points just inside and just outside tolerance', () {
      final regions = [_line('l1', 'abc', 10, 10)];
      expect(
        pointIsOnRecognizedText(
          regions: regions,
          point: const Point(x: 9, y: 12),
        ),
        isTrue,
      );
      expect(
        pointIsOnRecognizedText(
          regions: regions,
          point: const Point(x: 4, y: 12),
        ),
        isFalse,
      );
    });
  });

  group('loop classification', () {
    test('paragraph loop becomes text above character and area thresholds', () {
      final metrics = classifyLoop(
        regions: [_line('l1', 'hello', 10, 10)],
        stroke: _rect(8, 8, 66, 24),
      );

      expect(metrics.interpretation, LoopInterpretation.text);
      expect(metrics.characterCount, greaterThanOrEqualTo(3));
      expect(metrics.textAreaRatio, greaterThanOrEqualTo(0.12));
    });

    test('photo loop with no text becomes object', () {
      final metrics = classifyLoop(
        regions: [_line('l1', 'abc', 10, 10)],
        stroke: _rect(100, 100, 220, 220),
      );

      expect(metrics.interpretation, LoopInterpretation.object);
      expect(metrics.characterCount, 0);
    });

    test('photo with caption below ratio becomes object', () {
      final metrics = classifyLoop(
        regions: [_line('caption', 'abc', 110, 190)],
        stroke: _rect(80, 80, 240, 240),
      );

      expect(metrics.interpretation, LoopInterpretation.object);
      expect(metrics.characterCount, 3);
      expect(metrics.textAreaRatio, lessThan(0.12));
    });

    test('stray edge characters below minimum become object', () {
      final metrics = classifyLoop(
        regions: [_line('stray', 'ab', 10, 10)],
        stroke: _rect(8, 8, 45, 24),
      );

      expect(metrics.interpretation, LoopInterpretation.object);
      expect(metrics.characterCount, 2);
    });
  });
}

TextRegion _line(String id, String text, double left, double top) {
  final ranges = <TextCharacterRange>[
    for (var index = 0; index < text.length; index++)
      TextCharacterRange(
        start: index,
        end: index + 1,
        text: text[index],
        polygon: _rect(left + index * 10, top, left + index * 10 + 8, top + 10),
        geometryKind: CharacterGeometryKind.derivedCtcPolygon,
        confidence: 1,
      ),
  ];
  return TextRegion(
    id: id,
    level: TextRegionLevel.line,
    text: text,
    polygon: _rect(left, top, left + text.length * 10, top + 10),
    confidence: 1,
    readingOrder: 0,
    ranges: ranges,
  );
}

List<Point> _rect(double left, double top, double right, double bottom) => [
  Point(x: left, y: top),
  Point(x: right, y: top),
  Point(x: right, y: bottom),
  Point(x: left, y: bottom),
];
